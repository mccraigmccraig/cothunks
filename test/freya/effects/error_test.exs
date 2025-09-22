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
      require Freya.Con

      fv =
        Freya.Con.con [Error] do
          _ <- Error.throw_fx(:oops)
          Freer.return(:unreachable)
        end

      %Freya.RunOutcome{result: res} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert Freya.Result.type(res) == Freya.Freer.ErrorResult
      assert Freya.Result.value(res) == :oops
    end

    test "catch recovers from throw" do
      require Freer
      require Freya.Con

      fv =
        Freya.Con.con Error do
          res <-
            Error.catch_fx(
              Freya.Con.con Error do
                _ <- Error.throw_fx(:bad)
                Freer.return(:nope)
              end,
              fn err -> Freer.return({:recovered, err}) end
            )

          Freer.return(res)
        end

      %Freya.RunOutcome{result: res, outputs: _out} =
        fv |> ErrorHandler.interpret_error() |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == {:recovered, :bad}
    end

    test "catch passes through success" do
      require Freer
      require Freya.Con

      fv =
        Freya.Con.con Error do
          res <- Error.catch_fx(Freer.return(42), fn _ -> Freer.return(0) end)
          Freer.return(res)
        end

      %Freya.RunOutcome{result: res, outputs: _out} =
        fv |> ErrorHandler.interpret_error() |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == 42
    end
  end

  describe "composition with Writer and State" do
    test "writer before throw is kept; after is skipped" do
      require Freer
      require Freya.Con

      fv =
        Freya.Con.con [Error, Writer] do
          _ <- Writer.put(:before)
          _ <- Error.throw_fx(:bad)
          _ <- Writer.put(:after)
          Freer.return(:unreachable)
        end

      %Freya.RunOutcome{result: res, outputs: out} =
        fv |> ErrorHandler.interpret_error() |> WriterHandler.interpret_writer() |> Freer.run()

      assert out.writer == [:before]
      assert Freya.Result.type(res) == Freya.Freer.ErrorResult
      assert Freya.Result.value(res) == :bad
    end

    test "nested catch with state" do
      require Freer
      require Freya.Con

      fv =
        Freya.Con.con [Error, Writer] do
          # emulate state with Reader+Writer interpreter
          res <-
            Error.catch_fx(
              Freya.Con.con [Error, Writer] do
                _ <- Error.throw_fx(:inner)
                _ <- Writer.put(:after_throw)
                Freer.return(:nope)
              end,
              fn err ->
                Freya.Con.con [Writer] do
                  _ <- Writer.put({:handled, err})
                  Freer.return(:ok)
                end
              end
            )

          Freer.return(res)
        end

      %Freya.RunOutcome{result: res, outputs: out} =
        fv
        |> ErrorHandler.interpret_error()
        |> WriterHandler.interpret_writer()
        |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == :ok
      assert out[:writer] == [{:handled, :inner}]
    end
  end
end
