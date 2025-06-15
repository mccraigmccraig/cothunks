# Structured Logging Demo for Thunks.Freer
# This file demonstrates the advanced structured logging capabilities
# that enable computation persistence, resumption, and detailed tracing.

defmodule StructuredLoggingDemo do
  alias Thunks.Freer
  alias Thunks.Freer.{ComputationLog, LogEntry}

  # Example effect modules
  defmodule MathEffects do
    def number(n), do: Freer.send_effect(n, :number)
    def add(a, b), do: Freer.send_effect({:add, a, b}, :math)
    def multiply(a, b), do: Freer.send_effect({:multiply, a, b}, :math)
    def divide(a, b), do: Freer.send_effect({:divide, a, b}, :math)
  end

  defmodule AsyncEffects do
    def http_get(url), do: Freer.send_effect({:http_get, url}, :http)
    def sleep(ms), do: Freer.send_effect({:sleep, ms}, :async)
  end

  # Effect handlers
  defmodule Handlers do
    def run_math(computation) do
      Freer.handle_relay(
        computation,
        [:number, :math],
        &Freer.return/1,
        fn
          n, k when is_number(n) -> k.(n)
          {:add, a, b}, k -> k.(a + b)
          {:multiply, a, b}, k -> k.(a * b)
          {:divide, a, b}, k when b != 0 -> k.(a / b)
          {:divide, _a, 0}, _k -> raise "Division by zero"
        end
      )
    end

    def run_async(computation) do
      Freer.handle_relay(
        computation,
        [:http, :async],
        &Freer.return/1,
        fn
          {:http_get, url}, k ->
            # Simulate HTTP request
            IO.puts("Making HTTP request to: #{url}")
            result = %{status: 200, body: "Response from #{url}"}
            k.(result)

          {:sleep, ms}, k ->
            IO.puts("Sleeping for #{ms}ms")
            :timer.sleep(ms)
            k.(:ok)
        end
      )
    end
  end

  def demo_basic_logging do
    IO.puts("\n=== Basic Structured Logging Demo ===")

    import MathEffects

    computation =
      Freer.con([MathEffects]) do
        steps(
          a <- number(10),
          b <- number(5),
          sum <- add(a, b),
          result <- multiply(sum, 2)
        ) do
          divide(result, 3)
        end
      end

    {result, log} =
      computation
      |> Freer.handle_with_log()
      |> Handlers.run_math()
      |> Freer.run()

    IO.puts("Final result: #{result}")
    IO.puts("Number of logged steps: #{length(log.steps)}")
    IO.puts("Computation status: #{log.status}")

    # Show intermediate values
    IO.puts("\nIntermediate values:")

    log.steps
    |> Enum.reverse()
    |> Enum.each(fn step ->
      if step.output do
        IO.puts("  Step #{step.step_id}: #{step.effect} -> #{step.output}")
      end
    end)

    {result, log}
  end

  def demo_persistence_and_resumption do
    IO.puts("\n=== Computation Persistence and Resumption Demo ===")

    import MathEffects

    # Create a computation
    computation =
      Freer.con([MathEffects]) do
        steps(
          x <- number(7),
          y <- number(3),
          product <- multiply(x, y)
        ) do
          add(product, 5)
        end
      end

    # Run and log the computation
    {result, log} =
      computation
      |> Freer.handle_with_log()
      |> Handlers.run_math()
      |> Freer.run()

    IO.puts("Original computation result: #{result}")

    # Persist the log to JSON
    {:ok, json_log} = Freer.persist_log(log)
    IO.puts("Log persisted to JSON (#{byte_size(json_log)} bytes)")

    # Simulate saving to file (in real usage)
    # File.write!("computation_log.json", json_log)

    # Load the log back
    {:ok, loaded_log} = Freer.load_log(json_log)
    IO.puts("Log loaded successfully")
    IO.puts("Loaded log has #{length(loaded_log.steps)} steps")

    # Resume from the loaded log
    {resumed_result, _final_log} =
      computation
      |> Freer.resume_computation(loaded_log)
      |> Freer.run()

    IO.puts("Resumed computation result: #{resumed_result}")

    case resumed_result do
      {final_value, _log} when is_tuple(resumed_result) ->
        IO.puts("Successfully resumed with final value: #{final_value}")

      value ->
        IO.puts("Resumed computation returned: #{value}")
    end
  end

  def demo_yield_and_resume do
    IO.puts("\n=== Yield and Resume Demo ===")

    import MathEffects

    # Create a computation that yields
    yielding_computation =
      Freer.con([MathEffects]) do
        steps(
          a <- number(15),
          _ <- Freer.yield_computation("checkpoint_after_first_number"),
          b <- number(25),
          _ <- Freer.yield_computation("checkpoint_after_second_number"),
          sum <- add(a, b)
        ) do
          multiply(sum, 2)
        end
      end

    # Handle the yielding computation
    {status, yield_log} =
      yielding_computation
      |> Freer.handle_yield()
      |> Handlers.run_math()
      |> Freer.run()

    case status do
      :yielded ->
        IO.puts("Computation yielded at: #{yield_log.metadata.yield_info.yield_value}")
        IO.puts("Can be resumed later...")

        # In a real scenario, you would save yield_log and resume later
        # For demo purposes, let's show how to resume
        {resumed_result, _} =
          yielding_computation
          |> Freer.resume_computation(yield_log)
          |> Handlers.run_math()
          |> Freer.run()

        IO.puts("Resumed result: #{inspect(resumed_result)}")

      other ->
        IO.puts("Computation completed with result: #{inspect(other)}")
    end
  end

  def demo_error_handling_with_logging do
    IO.puts("\n=== Error Handling with Logging Demo ===")

    import MathEffects

    # Create a computation that will error
    error_computation =
      Freer.con([MathEffects]) do
        steps(
          a <- number(10),
          b <- number(0),
          # This will cause division by zero
          result <- divide(a, b)
        ) do
          result
        end
      end

    try do
      {_result, _log} =
        error_computation
        |> Freer.handle_with_log()
        |> Handlers.run_math()
        |> Freer.run()
    rescue
      error ->
        IO.puts("Computation failed with error: #{inspect(error)}")
        IO.puts("In a real system, you could examine the log to see what steps completed successfully")
    end
  end

  def demo_async_effects_with_logging do
    IO.puts("\n=== Async Effects with Logging Demo ===")

    import AsyncEffects
    import MathEffects

    # Create a computation that mixes sync and async effects
    async_computation =
      Freer.con([AsyncEffects, MathEffects]) do
        steps(
          response1 <- http_get("https://api.example.com/data"),
          _ <- sleep(100),
          response2 <- http_get("https://api.example.com/more-data"),
          count <- number(42)
        ) do
          {response1, response2, count}
        end
      end

    {result, log} =
      async_computation
      |> Freer.handle_with_log()
      |> Handlers.run_async()
      |> Handlers.run_math()
      |> Freer.run()

    IO.puts("Async computation completed")
    IO.puts("Result: #{inspect(result)}")
    IO.puts("Total steps logged: #{length(log.steps)}")

    # Show timing information
    IO.puts("\nStep timing:")

    log.steps
    |> Enum.reverse()
    |> Enum.each(fn step ->
      if step.effect != :pure do
        IO.puts("  #{step.effect} at #{step.timestamp}")
      end
    end)
  end

  def demo_log_analysis do
    IO.puts("\n=== Log Analysis Demo ===")

    # Create a more complex computation for analysis
    {_result, log} = demo_basic_logging()

    # Analyze the log
    IO.puts("\nLog Analysis:")
    IO.puts("- Total steps: #{length(log.steps)}")
    IO.puts("- Status: #{log.status}")

    # Group by effect type
    effect_counts =
      log.steps
      |> Enum.group_by(& &1.effect)
      |> Enum.map(fn {effect, steps} -> {effect, length(steps)} end)
      |> Enum.sort()

    IO.puts("- Effect counts:")

    Enum.each(effect_counts, fn {effect, count} ->
      IO.puts("  - #{effect}: #{count}")
    end)

    # Calculate computation duration
    timestamps = Enum.map(log.steps, & &1.timestamp)

    if length(timestamps) > 1 do
      duration = Enum.max(timestamps) - Enum.min(timestamps)
      IO.puts("- Total duration: #{duration} microseconds")
    end

    # Show the computation flow
    IO.puts("\nComputation flow:")

    log.steps
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.each(fn {step, idx} ->
      IO.puts("  #{idx + 1}. #{step.effect} -> #{step.output}")
    end)
  end

  def run_all_demos do
    IO.puts("🚀 Thunks.Freer Structured Logging Demonstration")
    IO.puts("=" |> String.duplicate(50))

    demo_basic_logging()
    demo_persistence_and_resumption()
    demo_yield_and_resume()
    demo_error_handling_with_logging()
    demo_async_effects_with_logging()
    demo_log_analysis()

    IO.puts("\n" <> ("=" |> String.duplicate(50)))
    IO.puts("✅ All demos completed successfully!")
    IO.puts("\nKey features demonstrated:")
    IO.puts("- ✅ Structured logging of all computation steps")
    IO.puts("- ✅ JSON serialization and persistence")
    IO.puts("- ✅ Computation resumption from logs")
    IO.puts("- ✅ Yield and resume capabilities")
    IO.puts("- ✅ Error handling with logging")
    IO.puts("- ✅ Async effects logging")
    IO.puts("- ✅ Log analysis and introspection")
    IO.puts("\nUse cases enabled:")
    IO.puts("- 🔄 Long-running process checkpointing")
    IO.puts("- 🐛 Detailed debugging and tracing")
    IO.puts("- 📊 Performance monitoring")
    IO.puts("- 🔁 Workflow resumption after interruption")
    IO.puts("- 🧪 Testing with deterministic replay")
  end
end

# Run the demo
StructuredLoggingDemo.run_all_demos()
