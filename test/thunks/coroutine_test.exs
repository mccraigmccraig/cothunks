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
          steps _ <- Ops.yield(42) do
            Freer.return("finished")
          end
        end

      # Run the coroutine
      result = Coroutine.run(computation)

      # It should yield 42
      assert {:yielded, 42, continuation} = result
      assert is_function(continuation, 1)

      # Resume with a value
      resumed = continuation.("resumed value")
      assert {:done, "finished"} = Coroutine.run(resumed)
    end

    test "multiple yields" do
      require Freer

      # Create a coroutine that yields multiple values
      computation =
        Freer.con Ops do
          steps a <- Ops.yield(1),
                b <- Ops.yield(a + 1),
                c <- Ops.yield(b + 1) do
            Freer.return(c + 1)
          end
        end

      # First yield
      {:yielded, 1, k1} = Coroutine.run(computation)

      # Resume with 10
      {:yielded, 11, k2} = Coroutine.run(k1.(10))

      # Resume with 20
      {:yielded, 31, k3} = Coroutine.run(k2.(20))

      # Resume with 30 and get final result
      {:done, 61} = Coroutine.run(k3.(30))
    end

    test "run_collecting helper" do
      require Freer

      computation =
        Freer.con Ops do
          steps a <- Ops.yield(1),
                b <- Ops.yield(a + 1),
                c <- Ops.yield(b + 1) do
            Freer.return(c + 1)
          end
        end

      # Run to completion, collecting all yields
      # Each yield gets the same resume value (10)
      {final, yields} =
        Coroutine.run_collecting(computation, [], fn v, acc -> {10, [v | acc]} end)

      assert final == 31  # 10 + 1 + 10 + 1 + 10
      assert yields == [1, 11, 21]
    end

    test "run_stream helper" do
      require Freer

      computation =
        Freer.con Ops do
          steps _ <- Ops.yield("first"),
                _ <- Ops.yield("second"),
                _ <- Ops.yield("third") do
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

      # Define a simple state handler
      defmodule State do
        def run_state(computation, initial_state) do
          computation
          |> Freer.handle_relay(
            [Thunks.Reader.Ops, Thunks.Writer.Ops],
            fn x -> Freer.return({x, initial_state}) end,
            fn
              {:put, new_state}, k -> k.(nil) |> Freer.bind(fn {x, _} -> Freer.return({x, new_state}) end)
              :get, k -> k.(initial_state)
            end
          )
        end
      end

      # Create a coroutine that uses state
      computation =
        Freer.con [Ops, Thunks.Reader, Thunks.Writer] do
          steps state <- Thunks.Reader.Ops.get(),
                _ <- Ops.yield(state),
                _ <- Thunks.Writer.Ops.put(state + 10),
                new_state <- Thunks.Reader.Ops.get(),
                _ <- Ops.yield(new_state) do
            Freer.return("final")
          end
        end

      # First run with state
      {:yielded, 5, k1} = computation |> State.run_state(5) |> Coroutine.run()

      # Resume and get second yield
      {:yielded, 15, k2} = k1.(nil) |> Coroutine.run()

      # Resume and get final result
      {:done, {{"final", 15}}} = k2.(nil) |> Coroutine.run()
    end
  end
end
