defmodule Thunks.CoroutineTest do
  use ExUnit.Case

  require Logger

  alias Thunks.Freer
  alias Thunks.State
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
      result = computation |> Coroutine.run() |> Freer.run()

      # It should yield 42
      assert %Thunks.Coroutine.Status.Continue{value: 42, continuation: continuation} = result

      assert is_function(continuation, 1)

      # Resume with a value
      resumed = Coroutine.resume(result, "resumed value")
      assert %Thunks.Coroutine.Status.Done{value: "finished: resumed value"} = Freer.run(resumed)
    end

    test "multiple yields" do
      require Freer

      # Keep the simple test as well
      computation =
        Freer.con Ops do
          steps a <- yield("first"),
                b <- yield("second: #{a}") do
            Freer.return("final: #{b}")
          end
        end

      # First yield
      result = computation |> Coroutine.run() |> Freer.run()
      assert %Thunks.Coroutine.Status.Continue{value: "first", continuation: _k1} = result

      # Second yield
      result2 = result |> Coroutine.resume(10) |> Freer.run()
      assert %Thunks.Coroutine.Status.Continue{value: "second: 10", continuation: _k2} = result2

      # Final result
      result3 = result2 |> Coroutine.resume(20) |> Freer.run()
      assert %Thunks.Coroutine.Status.Done{value: "final: 20"} = result3
    end

    # test "multiple yields" do
    #   require Freer

    #   # Create a coroutine that yields multiple values
    #   computation =
    #     Freer.con Ops do
    #       steps a <- yield(1),
    #             b <- yield(a + 1),
    #             c <- yield(b + 1) do
    #         Freer.return(c + 1)
    #       end
    #     end

    #   # Let's trace the execution manually to understand what's happening
    #   result = Coroutine.run(computation)
    #   %Thunks.Coroutine.Status.Continue{value: 1, continuation: k1} = Freer.run(result)

    #   resumed1 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: 1, continuation: k1}, 2)

    #   %Thunks.Coroutine.Status.Continue{value: v2, continuation: k2} = Freer.run(resumed1)

    #   resumed2 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: v2, continuation: k2}, 4)

    #   %Thunks.Coroutine.Status.Continue{value: v3, continuation: k3} = Freer.run(resumed2)

    #   resumed3 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: v3, continuation: k3}, 8)

    #   %Thunks.Coroutine.Status.Done{value: v4} = Freer.run(resumed3)

    #   assert {v2, v3, v4} == {3, 5, 9}

    #   # try resuming with some different values

    #   # Resume with 10
    #   resumed10 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: 1, continuation: k1}, 10)

    #   assert %Thunks.Coroutine.Status.Continue{value: 11, continuation: _k2} =
    #            Freer.run(resumed10)

    #   # Resume with 20
    #   resumed20 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: v2, continuation: k2}, 20)

    #   assert %Thunks.Coroutine.Status.Continue{value: 21, continuation: _k3} =
    #            Freer.run(resumed20)

    #   # Resume with 30 and get final result
    #   resumed30 =
    #     Coroutine.resume(%Thunks.Coroutine.Status.Continue{value: v3, continuation: k3}, 30)

    #   assert %Thunks.Coroutine.Status.Done{value: 31} = Freer.run(resumed30)
    # end

    # test "run_collecting helper" do
    #   require Freer

    #   computation =
    #     Freer.con Ops do
    #       steps a <- yield(1),
    #             b <- yield(a + 1),
    #             c <- yield(b + 1) do
    #         Freer.return(a + b + c + 1)
    #       end
    #     end

    #   # Run to completion, collecting all yields
    #   # Each yield gets the same resume value (10)
    #   {final, yields} =
    #     Coroutine.run_collecting(computation, [], fn v, acc -> {v + 10, [v | acc]} end)

    #   # This is the actual value: 1 + 11 + 21 + 34
    #   assert final == 67
    #   assert yields == [1, 12, 23]
    # end

    # test "run_stream helper" do
    #   require Freer

    #   computation =
    #     Freer.con Ops do
    #       steps _ <- yield("first"),
    #             _ <- yield("second"),
    #             _ <- yield("third") do
    #         Freer.return("done")
    #       end
    #     end

    #   # Convert to a stream and collect results
    #   results = Coroutine.run_stream(computation) |> Enum.to_list()

    #   assert results == [
    #            {:yielded, "first"},
    #            {:yielded, "second"},
    #            {:yielded, "third"},
    #            {:result, "done"}
    #          ]
    # end
  end

  describe "combining with other effects" do
    test "coroutine with state" do
      require Freer

      computation =
        Freer.con [Ops, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps state <- get(),
                r1 <- yield("State is: #{state}"),
                put(state + r1),
                new_state <- get(),
                r2 <- yield("New state is: #{new_state}") do
            Freer.return("Final resume: #{r2}")
          end
        end

      # First run the computation through the state handler with initial state 5
      result1 = computation |> Thunks.State.run(5) |> Coroutine.run() |> Freer.run()

      assert %Thunks.Coroutine.Status.Continue{value: "State is: 5", continuation: _k1} = result1

      result2 = result1 |> Coroutine.resume(10) |> Freer.run()

      assert %Thunks.Coroutine.Status.Continue{value: "New state is: 15", continuation: _k2} =
               result2

      result3 = result2 |> Coroutine.resume(100) |> Freer.run()

      assert %Thunks.Coroutine.Status.Done{value: {"Final resume: 100", 15}} = result3
    end
  end

  describe "trying the everything handler" do
    test "everything handler" do
      require Freer

      computation =
        Freer.con [Ops, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps state <- get(),
                r1 <- yield("State is: #{state}"),
                put(state + r1),
                new_state <- get(),
                r2 <- yield("New state is: #{new_state}") do
            Freer.return("Final resume: #{r2}")
          end
        end

      result1 =
        computation |> Freer.handle_all() |> State.run(5) |> Coroutine.run() |> Freer.run()

      result2 = result1 |> Coroutine.resume(10) |> Freer.run()
      _result3 = result2 |> Coroutine.resume(100) |> Freer.run()
    end
  end
end
