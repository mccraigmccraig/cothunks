defmodule Thunks.CoroutineTest do
  use ExUnit.Case

  alias Thunks.Freer
  alias Thunks.Coroutine
  alias Thunks.Coroutine.Ops

  describe "basic coroutine operations" do
    test "simple yield and resume" do
      require Freer

      # Create a coroutine that yields a value and returns another
      computation =
        Freer.con Ops do
          steps a <- yield(42) do
            Freer.return("finished: " <> a)
          end
        end

      # Run the coroutine
      result = Coroutine.run(computation)
      extracted = Coroutine.extract(result)

      # It should yield 42
      assert %Thunks.Coroutine.Yielded{value: 42, continuation: continuation} = extracted
      assert is_function(continuation, 1)

      # Resume with a value
      resumed = Coroutine.resume(extracted, "resumed value")
      assert %Thunks.Coroutine.Done{value: "finished: resumed value"} = Coroutine.extract(resumed)
    end

    test "multiple yields" do
      require Freer

      # Create a coroutine that yields multiple values
      computation =
        Freer.con Ops do
          steps a <- yield(1),
                b <- yield(a + 1),
                c <- yield(b + 1) do
            Freer.return(c + 1)
          end
        end

      # Let's trace the execution manually to understand what's happening
      result = Coroutine.run(computation)
      %Thunks.Coroutine.Yielded{value: 1, continuation: k1} = Coroutine.extract(result)

      resumed1 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: 1, continuation: k1}, 2)
      %Thunks.Coroutine.Yielded{value: v2, continuation: k2} = Coroutine.extract(resumed1)

      resumed2 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: v2, continuation: k2}, 4)
      %Thunks.Coroutine.Yielded{value: v3, continuation: k3} = Coroutine.extract(resumed2)

      resumed3 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: v3, continuation: k3}, 8)
      %Thunks.Coroutine.Done{value: v4} = Coroutine.extract(resumed3)

      assert {v2, v3, v4} == {3, 5, 9}

      # try resuming with some different values

      # Resume with 10
      resumed10 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: 1, continuation: k1}, 10)

      assert %Thunks.Coroutine.Yielded{value: 11, continuation: _k2} =
               Coroutine.extract(resumed10)

      # Resume with 20
      resumed20 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: v2, continuation: k2}, 20)

      assert %Thunks.Coroutine.Yielded{value: 21, continuation: _k3} =
               Coroutine.extract(resumed20)

      # Resume with 30 and get final result
      resumed30 = Coroutine.resume(%Thunks.Coroutine.Yielded{value: v3, continuation: k3}, 30)
      assert %Thunks.Coroutine.Done{value: 31} = Coroutine.extract(resumed30)
    end

    test "run_collecting helper" do
      require Freer

      computation =
        Freer.con Ops do
          steps a <- yield(1),
                b <- yield(a + 1),
                c <- yield(b + 1) do
            Freer.return(a + b + c + 1)
          end
        end

      # Run to completion, collecting all yields
      # Each yield gets the same resume value (10)
      {final, yields} =
        Coroutine.run_collecting(computation, [], fn v, acc -> {v + 10, [v | acc]} end)

      # This is the actual value: 1 + 11 + 21 + 34
      assert final == 67
      assert yields == [1, 12, 23]
    end

    test "run_stream helper" do
      require Freer

      computation =
        Freer.con Ops do
          steps _ <- yield("first"),
                _ <- yield("second"),
                _ <- yield("third") do
            Freer.return("done")
          end
        end

      # Convert to a stream and collect results
      results = Coroutine.run_stream(computation) |> Enum.to_list()

      assert results == [
               {:yielded, "first"},
               {:yielded, "second"},
               {:yielded, "third"},
               {:result, "done"}
             ]
    end
  end

  describe "combining with other effects" do
    test "coroutine with state" do
      require Freer

      # Create a simpler test that demonstrates coroutines with state
      # This avoids the complex interaction between the two effect systems
      computation =
        Freer.con [Ops, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps state <- get(),
                _ <- yield("State is: #{state}"),
                _ <- put(state + 10),
                new_state <- get(),
                _ <- yield("New state is: #{new_state}") do
            Freer.return("Final state: #{new_state}")
          end
        end

      # First run the computation through the state handler with initial state 5
      coroutine_handled = computation |> Thunks.State.run(5) |> Coroutine.run()

      # Extract the first yield
      extracted1 = Coroutine.extract(coroutine_handled)
      assert %Thunks.Coroutine.Yielded{value: "State is: 5", continuation: _k1} = extracted1

      # Extract the second yield
      extracted2 = extracted1 |> Coroutine.resume(10) |> Coroutine.extract()
      assert %Thunks.Coroutine.Yielded{value: "New state is: 15", continuation: _k2} = extracted2

      # Run the final computation through state handler
      final_state_handled = extracted2 |> Coroutine.resume(10) |> Coroutine.extract()

      # Extract the final result
      final_result = Coroutine.extract(Coroutine.run(final_state_handled))
      assert %Thunks.Coroutine.Done{value: {"Final state: 15", 15}} = final_result
    end

    test "simple coroutine" do
      require Freer

      # Keep the simple test as well
      computation =
        Freer.con Ops do
          steps _ <- yield("first"),
                _ <- yield("second") do
            Freer.return("final")
          end
        end

      # First yield
      result = Coroutine.run(computation)
      extracted = Coroutine.extract(result)
      assert %Thunks.Coroutine.Yielded{value: "first", continuation: _k1} = extracted

      # Second yield
      resumed = Coroutine.resume(extracted, nil)
      extracted2 = Coroutine.extract(resumed)
      assert %Thunks.Coroutine.Yielded{value: "second", continuation: _k2} = extracted2

      # Final result
      resumed2 = Coroutine.resume(extracted2, nil)
      extracted3 = Coroutine.extract(resumed2)
      assert %Thunks.Coroutine.Done{value: "final"} = extracted3
    end
  end
end
