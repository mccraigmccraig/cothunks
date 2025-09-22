defmodule Freya.ConElseErrorTest do
  use ExUnit.Case

  alias Freya.Freer
  alias Freya.Effects.{Error, ErrorHandler, Writer, WriterHandler}

  describe "con ... else error handling" do
    test "matches a pattern and recovers" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- throw_fx({:invalid, 3})
          return(:unreachable)
        else
          {:invalid, n} -> Freer.return({:fixed, n + 1})
        end

      %Freya.RunOutcome{result: res, outputs: _out} =
        fv |> ErrorHandler.interpret_error() |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == {:fixed, 4}
    end

    test "no matching clause rethrows" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- throw_fx(:nope)
          return(:unreachable)
        else
          :other -> Freer.return(:ok)
        end

      %Freya.RunOutcome{result: res} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert Freya.Result.type(res) == Freya.Freer.ErrorResult
      assert Freya.Result.value(res) == :nope
    end

    test "handler clause can perform effects" do
      require Freer

      fv =
        Freer.con [Error, Writer] do
          _ <- put(:before)
          _ <- throw_fx(:bad)
          _ <- put(:after)
          return(:nope)
        else
          :bad ->
            _ <- put({:handled, :bad})
            return(:ok)
        end

      %Freya.RunOutcome{result: res, outputs: out} =
        fv
        |> ErrorHandler.interpret_error()
        |> WriterHandler.interpret_writer()
        |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == :ok
      assert out.writer == [:before, {:handled, :bad}]
    end

    test "user-supplied default else clause handles all and prevents rethrow" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- throw_fx(:anything)
          return(:unreachable)
        else
          _ -> Freer.return(:handled)
        end

      %Freya.RunOutcome{result: res, outputs: _out} =
        fv |> ErrorHandler.interpret_error() |> Freer.run()

      assert Freya.Result.type(res) == Freya.Freer.OkResult
      assert Freya.Result.value(res) == :handled
    end
  end
end
