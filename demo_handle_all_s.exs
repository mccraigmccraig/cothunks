#!/usr/bin/env elixir

# Demo script showing the handle_all_s functionality
# Run with: elixir demo_handle_all_s.exs

Code.require_file("lib/thunks/freer.ex")
Code.require_file("lib/thunks/freer_ops.ex")
Code.require_file("lib/thunks/reader.ex")
Code.require_file("lib/thunks/writer.ex")
Code.require_file("lib/thunks/state.ex")

defmodule Demo do
  require Logger
  require Freya.Freer
  alias Freya.Freer
  alias Freya.{Reader, Writer, State}

  # Define a simple calculator effect
  defmodule CalcGrammar do
    def number(n), do: {:number, n}
    def add(a, b), do: {:add, a, b}
    def multiply(a, b), do: {:multiply, a, b}
    def divide(a, b), do: {:divide, a, b}
  end

  defmodule Calc do
    use Freya.FreerOps, ops: CalcGrammar
  end

  # Interpreter for calculator effects
  def run_calc(computation) do
    computation
    |> Freer.handle_relay(
      [Calc],
      &Freer.return/1,
      fn
        {:number, n}, k -> k.(n)
        {:add, a, b}, k -> k.(a + b)
        {:multiply, a, b}, k -> k.(a * b)
        {:divide, a, b}, k when b != 0 -> k.(a / b)
        {:divide, a, b}, _k -> Freer.return({:error, "Division by zero: #{a}/#{b}"})
      end
    )
  end

  def demo_basic_logging do
    IO.puts("\n=== Demo 1: Basic State Logging ===")
    
    computation = 
      Freer.con Calc do
        steps a <- number(10),
              b <- number(5),
              c <- multiply(a, b) do
          add(a, c)
        end
      end

    result = 
      computation
      |> Freer.handle_all_s(%{step: 0, operations: []})
      |> run_calc()
      |> Freer.run()

    IO.puts("Result: #{inspect(result)}")
  end

  def demo_with_reader_writer do
    IO.puts("\n=== Demo 2: With Reader and Writer Effects ===")

    computation =
      Freer.con [Calc, Reader.Ops, Writer.Ops] do
        steps initial <- get(),
              _ <- put("Starting with #{initial}"),
              a <- number(initial),
              b <- multiply(a, 3),
              _ <- put("Multiplied by 3: #{b}"),
              c <- add(a, b) do
          put("Final result: #{c}")
          |> Freer.bind(fn _ -> Freer.return(c) end)
        end
      end

    result =
      computation
      |> Freer.handle_all_s(%{debug: true, trace_id: "calc-001"})
      |> run_calc()
      |> Reader.run(7)  # Initial value
      |> Writer.run()
      |> Freer.run()

    IO.puts("Result: #{inspect(result)}")
  end

  def demo_custom_state_handler do
    IO.puts("\n=== Demo 3: Custom State Handler ===")

    computation =
      Freer.con Calc do
        steps a <- number(20),
              b <- divide(a, 4),
              c <- multiply(b, 3) do
          add(a, c)
        end
      end

    # Custom return function that logs the final state
    custom_ret = fn state -> 
      fn value -> 
        updated_state = Map.update!(state, :operations, &(&1 + 1))
        IO.puts("Custom handler: Final state = #{inspect(updated_state)}")
        Freer.return({:custom_result, value, updated_state})
      end 
    end

    result =
      computation
      |> Freer.handle_all_s(%{operations: 0, start_time: System.system_time()}, custom_ret)
      |> run_calc()
      |> Freer.run()

    IO.puts("Result: #{inspect(result)}")
  end

  def demo_with_state_effect do
    IO.puts("\n=== Demo 4: With Stateful Computation ===")

    computation =
      Freer.con [Calc, Reader.Ops, Writer.Ops] do
        steps counter <- get(),
              _ <- put(counter + 1),  # Increment counter
              a <- number(counter * 5),
              new_counter <- get(),
              b <- multiply(a, new_counter) do
          add(a, b)
        end
      end

    result =
      computation
      |> Freer.handle_all_s(%{debug_level: :verbose, session: "demo-4"})
      |> run_calc()
      |> State.run(3)  # Initial counter value
      |> Freer.run()

    IO.puts("Result: #{inspect(result)}")
  end

  def run_all_demos do
    IO.puts("🚀 Demonstrating handle_all_s - Stateful Effect Logging")
    IO.puts("=" |> String.duplicate(60))
    
    demo_basic_logging()
    demo_with_reader_writer()
    demo_custom_state_handler()
    demo_with_state_effect()
    
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("✅ All demos completed!")
    IO.puts("\nKey observations:")
    IO.puts("• handle_all_s threads state through all computations")
    IO.puts("• It logs every Pure and Impure effect with state information")
    IO.puts("• State is preserved but doesn't affect the actual computation")
    IO.puts("• Can be combined with any other effect handlers")
    IO.puts("• Custom return functions allow flexible result formatting")
  end
end

# Run the demos
Demo.run_all_demos()
