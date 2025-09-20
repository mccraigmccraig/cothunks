defmodule Freya.Effects.ErrorTest do
  use ExUnit.Case

  alias Freya.Freer
  alias Freya.Effects.Error
  alias Freya.Effects.ErrorHandler
  alias Freya.Effects.Writer
  alias Freya.Effects.WriterHandler

  describe "throw/catch basics" do
    test "throw without catch propagates error" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- Error.throw_fx(:oops)
          Freer.return(:unreachable)
        end

      %Freya.Result{outputs: out} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert out[:error] == :oops
    end

    test "catch recovers from throw" do
      require Freer

      fv =
        Freer.con Error do
          res <-
            Error.catch_fx(
              Freer.con Error do
                _ <- Error.throw_fx(:bad)
                Freer.return(:nope)
              end,
              fn err -> Freer.return({:recovered, err}) end
            )

          Freer.return(res)
        end

      %Freya.Result{value: v, outputs: out} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert v == {:recovered, :bad}
      refute Map.has_key?(out, :error)
    end

    test "catch passes through success" do
      require Freer

      fv =
        Freer.con Error do
          res <- Error.catch_fx(Freer.return(42), fn _ -> Freer.return(0) end)
          Freer.return(res)
        end

      %Freya.Result{value: v, outputs: out} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert v == 42
      assert out == %{}
    end
  end

  describe "composition with Writer and State" do
    test "writer before throw is kept; after is skipped" do
      require Freer

      fv =
        Freer.con [Error, Writer] do
          _ <- Writer.put(:before)
          _ <- Error.throw_fx(:bad)
          _ <- Writer.put(:after)
          Freer.return(:unreachable)
        end

      %Freya.Result{outputs: out} =
        fv |> ErrorHandler.interpret_error() |> WriterHandler.interpret_writer() |> Freer.run()

      assert out.writer == [:before]
      assert out.error == :bad
    end

    test "nested catch with state" do
      require Freer

      fv =
        Freer.con [Error, Writer] do
          # emulate state with Reader+Writer interpreter
          res <-
            Error.catch_fx(
              Freer.con [Error, Writer] do
                _ <- Error.throw_fx(:inner)
                _ <- Writer.put(:after_throw)
                Freer.return(:nope)
              end,
              fn err ->
                Freer.con [Writer] do
                  _ <- Writer.put({:handled, err})
                  Freer.return(:ok)
                end
              end
            )

          Freer.return(res)
        end

      %Freya.Result{value: v, outputs: out} =
        fv
        |> ErrorHandler.interpret_error()
        |> WriterHandler.interpret_writer()
        |> Freer.run()

      assert v == :ok
      assert out[:writer] == [{:handled, :inner}]
      refute Map.has_key?(out, :error)
    end
  end
end
