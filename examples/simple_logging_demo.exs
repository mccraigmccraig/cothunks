# Simple Structured Logging Demo for Thunks.Freer
# This demonstrates the structured logging capabilities using direct bind operations

defmodule SimpleLoggingDemo do
  alias Thunks.Freer
  alias Thunks.Freer.{ComputationLog, LogEntry}

  # Simple effect functions
  def number(n), do: Freer.send_effect(n, :number)
  def add(a, b), do: Freer.send_effect({:add, a, b}, :math)
  def multiply(a, b), do: Freer.send_effect({:multiply, a, b}, :math)

  # Effect handler
  def run_math(computation) do
    Freer.handle_relay(
      computation,
      [:number, :math],
      &Freer.return/1,
      fn
        n, k when is_number(n) -> k.(n)
        {:add, a, b}, k -> k.(a + b)
        {:multiply, a, b}, k -> k.(a * b)
      end
    )
  end

  def demo_basic_logging do
    IO.puts("\n=== Basic Structured Logging Demo ===")

    # Create a simple computation using bind operations
    computation =
      number(10)
      |> Freer.bind(fn a ->
        number(5)
        |> Freer.bind(fn b ->
          add(a, b)
          |> Freer.bind(fn sum ->
            multiply(sum, 2)
          end)
        end)
      end)

    # Run with logging
    {result, log} =
      computation
      |> Freer.handle_with_log()
      |> run_math()
      |> Freer.run()

    IO.puts("Final result: #{result}")
    IO.puts("Number of logged steps: #{length(log.steps)}")
    IO.puts("Computation status: #{log.status}")

    # Show intermediate values
    IO.puts("\nIntermediate values:")
    log.steps
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.each(fn {step, idx} ->
      if step.output do
        IO.puts("  #{idx + 1}. #{step.effect} -> #{step.output}")
      end
    end)

    {result, log}
  end

  def demo_persistence do
    IO.puts("\n=== Persistence Demo ===")

    # Simple computation
    computation =
      number(7)
      |> Freer.bind(fn x ->
        number(3)
        |> Freer.bind(fn y ->
          multiply(x, y)
          |> Freer.bind(fn product ->
            add(product, 5)
          end)
        end)
      end)

    # Run and log
    {result, log} =
      computation
      |> Freer.handle_with_log()
      |> run_math()
      |> Freer.run()

    IO.puts("Original result: #{result}")

    # Persist to JSON
    {:ok, json_log} = Freer.persist_log(log)
    IO.puts("Log persisted (#{byte_size(json_log)} bytes)")

    # Load back
    {:ok, loaded_log} = Freer.load_log(json_log)
    IO.puts("Log loaded with #{length(loaded_log.steps)} steps")

    # Resume computation
    {resumed_result, _final_log} =
      computation
      |> Freer.resume_computation(loaded_log)
      |> Freer.run()

    case resumed_result do
      {final_value, _log} ->
        IO.puts("Resumed with cached result: #{final_value}")
      value ->
        IO.puts("Resumed result: #{value}")
    end
  end

  def demo_yield_resume do
    IO.puts("\n=== Yield and Resume Demo ===")

    # Computation with yield
    computation =
      number(15)
      |> Freer.bind(fn a ->
        Freer.yield_computation("checkpoint_1")
        |> Freer.bind(fn _ ->
          number(25)
          |> Freer.bind(fn b ->
            add(a, b)
          end)
        end)
      end)

    # Handle yield
    {status, yield_log} =
      computation
      |> Freer.handle_yield()
      |> run_math()
      |> Freer.run()

    case status do
      :yielded ->
        IO.puts("Computation yielded at: #{yield_log.metadata.yield_info.yield_value}")
        IO.puts("Yield log has #{length(yield_log.steps)} steps")

      other ->
        IO.puts("Computation completed: #{inspect(other)}")
    end
  end

  def demo_log_analysis do
    IO.puts("\n=== Log Analysis Demo ===")

    # Run a computation to analyze
    {result, log} = demo_basic_logging()

    IO.puts("\nDetailed Analysis:")
    IO.puts("- Final result: #{result}")
    IO.puts("- Total steps: #{length(log.steps)}")
    IO.puts("- Status: #{log.status}")

    # Effect type analysis
    effect_counts =
      log.steps
      |> Enum.group_by(& &1.effect)
      |> Enum.map(fn {effect, steps} -> {effect, length(steps)} end)
      |> Enum.sort()

    IO.puts("- Effects used:")
    Enum.each(effect_counts, fn {effect, count} ->
      IO.puts("  - #{effect}: #{count} times")
    end)

    # Timing analysis
    timestamps = Enum.map(log.steps, & &1.timestamp)
    if length(timestamps) > 1 do
      duration = Enum.max(timestamps) - Enum.min(timestamps)
      IO.puts("- Total duration: #{duration} microseconds")
    end

    # Step-by-step flow
    IO.puts("\nExecution flow:")
    log.steps
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.each(fn {step, idx} ->
      if step.output do
        input_str = if step.input, do: inspect(step.input), else: "nil"
        IO.puts("  #{idx + 1}. #{step.effect}(#{input_str}) -> #{step.output} [#{step.step_type}]")
      end
    end)
  end

  def demo_error_handling do
    IO.puts("\n=== Error Handling Demo ===")

    # Create computation that will error
    error_computation =
      number(10)
      |> Freer.bind(fn a ->
        number(0)
        |> Freer.bind(fn b ->
          # This will cause error in a real division handler
          Freer.send_effect({:divide, a, b}, :math)
        end)
      end)

    # Modified handler that handles division
    error_handler = fn computation ->
      Freer.handle_relay(
        computation,
        [:number, :math],
        &Freer.return/1,
        fn
          n, k when is_number(n) -> k.(n)
          {:add, a, b}, k -> k.(a + b)
          {:multiply, a, b}, k -> k.(a * b)
          {:divide, _a, 0}, _k -> raise "Division by zero error"
          {:divide, a, b}, k -> k.(a / b)
        end
      )
    end

    try do
      {_result, _log} =
        error_computation
        |> Freer.handle_with_log()
        |> error_handler.()
        |> Freer.run()
    rescue
      error ->
        IO.puts("Caught error: #{inspect(error)}")
        IO.puts("In a real system, we could examine the log to see completed steps")
    end
  end

  def run_all_demos do
    IO.puts("🚀 Simple Thunks.Freer Structured Logging Demo")
    IO.puts("=" |> String.duplicate(60))

    demo_basic_logging()
    demo_persistence()
    demo_yield_resume()
    demo_log_analysis()
    demo_error_handling()

    IO.puts("\n" <> ("=" |> String.duplicate(60)))
    IO.puts("✅ All demos completed!")
    IO.puts("\nKey Features Demonstrated:")
    IO.puts("- ✅ Structured logging of computation steps")
    IO.puts("- ✅ JSON persistence and loading")
    IO.puts("- ✅ Computation resumption from logs")
    IO.puts("- ✅ Yield and resume capabilities")
    IO.puts("- ✅ Detailed log analysis")
    IO.puts("- ✅ Error handling with logging context")
    IO.puts("\nBenefits:")
    IO.puts("- 🔄 Avoid redundant computation on resume")
    IO.puts("- 🐛 Detailed debugging and tracing")
    IO.puts("- 📊 Performance monitoring and analysis")
    IO.puts("- 🔁 Workflow persistence and resumption")
    IO.puts("- 🧪 Deterministic testing and replay")
  end
end

# Run the demos
SimpleLoggingDemo.run_all_demos()
