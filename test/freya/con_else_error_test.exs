defmodule Freya.ConElseErrorTest do
  use ExUnit.Case

  alias Freya.Freer
  alias Freya.Effects.{Error, ErrorHandler, Writer, WriterHandler}

  describe "con ... else error handling" do
    test "matches a pattern and recovers" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- Error.throw_fx({:invalid, 3})
          Freer.return(:unreachable)
        else
          {:invalid, n} -> Freer.return({:fixed, n + 1})
        end

      %Freya.Result{value: v, outputs: out} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert v == {:fixed, 4}
      refute Map.has_key?(out, :error)
    end

    test "no matching clause rethrows" do
      require Freer

      fv =
        Freer.con [Error] do
          _ <- Error.throw_fx(:nope)
          Freer.return(:unreachable)
        else
          :other -> Freer.return(:ok)
        end

      %Freya.Result{outputs: out} = fv |> ErrorHandler.interpret_error() |> Freer.run()
      assert out[:error] == :nope
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

      %Freya.Result{value: v, outputs: out} =
        fv
        |> ErrorHandler.interpret_error()
        |> WriterHandler.interpret_writer()
        |> Freer.run()

      assert v == :ok
      assert out.writer == [:before, {:handled, :bad}]
      refute Map.has_key?(out, :error)
    end
  end
end
