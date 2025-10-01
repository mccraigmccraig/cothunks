defmodule Freya.Effects.CoroutineTest do
  use ExUnit.Case

  require Logger
  import Freya.Con

  alias Freya.Freer
  alias Freya.Effects.EffectLogger
  alias Freya.Effects.Coroutine
  alias Freya.Freer
  alias Freya.RunOutcome
  alias Freya.Run
  alias Freya.YieldResult
  alias Freya.OkResult

  describe "basic coroutine operations" do
    test "simple yield and resume" do
      # Create a coroutine that yields a value and returns another
      computation =
        con Coroutine do
          a <- yield(42)
          return("finished: " <> inspect(a))
        end

      runner =
        Run.with_handlers(c: Coroutine.Handler)

      outcome = Run.run(computation, runner)
      assert %RunOutcome{result: %YieldResult{value: 42}} = outcome

      outcome2 = Coroutine.Handler.resume(outcome, 100, runner)
      assert %Freya.RunOutcome{result: %OkResult{value: "finished: 100"}} = outcome2
    end

    test "multiple yields" do
      require Freer

      # Keep the simple test as well
      computation =
        con Coroutine do
          a <- yield("first")
          b <- yield("second: #{a}")
          return("final: #{a + b}")
        end

      # First yield
      runner =
        Run.with_handlers(
          l: EffectLogger.Handler,
          c: Coroutine.Handler
        )

      outcome = Run.run(computation, runner)
      assert %RunOutcome{result: %YieldResult{value: "first"}} = outcome

      outcome2 = Coroutine.Handler.resume(outcome, 100, runner)
      assert %Freya.RunOutcome{result: %YieldResult{value: "second: 100"}} = outcome2

      outcome3 = Coroutine.Handler.resume(outcome2, 50, runner)
      assert %Freya.RunOutcome{result: %OkResult{value: "final: 150"}} = outcome3

      Logger.error("#{__MODULE__}.log\n#{inspect(outcome3, pretty: true)}")
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

  # describe "combining with other effects" do
  #   test "coroutine with state" do
  #     require Freer

  #     computation =
  #       Freya.Con.con [Coroutine, Freya.Effects.Reader, Freya.Effects.Writer] do
  #         state <- get()
  #         r1 <- yield("State is: #{state}")
  #         put(state + r1)
  #         new_state <- get()
  #         r2 <- yield("New state is: #{new_state}")
  #         Freer.return("Final resume: #{r2}")
  #       end

  #     # First run the computation through the state handler with initial state 5
  #     result1 =
  #       computation
  #       |> Freya.Effects.State.interpret_state(5)
  #       |> CoroutineHandler.interpret_coroutine()
  #       |> Freer.run()

  #     assert %RunOutcome{
  #              result: %Freya.YieldResult{value: "State is: 5", continuation: _k1}
  #            } =
  #              result1

  #     result2 = result1 |> CoroutineHandler.resume(10) |> Freer.run()

  #     assert %RunOutcome{
  #              result: %Freya.YieldResult{value: "New state is: 15", continuation: _k2}
  #            } = result2

  #     result3 = result2 |> CoroutineHandler.resume(100) |> Freer.run()

  #     assert %RunOutcome{
  #              result: %Freya.OkResult{value: "Final resume: 100"},
  #              outputs: %{state: 15}
  #            } = result3
  #   end
  # end

  # describe "trying the everything handler" do
  #   test "everything handler" do
  #     require Freer

  #     computation =
  #       Freya.Con.con [Coroutine, Freya.Effects.Reader, Freya.Effects.Writer] do
  #         state <- get()
  #         r1 <- yield("State is: #{state}")
  #         put(state + r1)
  #         new_state <- get()
  #         r2 <- yield("New state is: #{new_state}")
  #         Freer.return("Final resume: #{r2}")
  #       end

  #     result1 =
  #       computation
  #       |> State.interpret_state(5)
  #       |> CoroutineHandler.interpret_coroutine()
  #       |> Freer.run()

  #     result2 = result1 |> CoroutineHandler.resume(10) |> Freer.run()
  #     _result3 = result2 |> CoroutineHandler.resume(100) |> Freer.run()
  #   end
  # end
end
