defmodule Freya.DefconTest do
  use ExUnit.Case

  alias Freya.Freer
  alias Freya.Effects.{Reader, ReaderHandler, Writer, WriterHandler, Error, ErrorHandler}

  defmodule DefconExample do
    require Freer

    Freer.defcon sum_env(a, b), [Reader] do
      c <- get()
      return(a + b + c)
    end

    Freer.defconp write_and_sum(a, b), [Writer] do
      put(a)
      put(b)
      return(a + b)
    end

    def call_private(a, b) do
      write_and_sum(a, b)
    end

    Freer.defcon safe_div(a, b), [Error] do
      if b == 0 do
        throw_fx(:zero)
      else
        return(a / b)
      end
    else
      :zero -> return(:infty)
    end
  end

  test "defcon with Reader returns expected sum" do
    out = DefconExample.sum_env(1, 2) |> ReaderHandler.interpret_reader(3) |> Freer.run()
    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: 6}} = out
  end

  test "defconp with Writer accumulates outputs" do
    out = DefconExample.call_private(4, 5) |> WriterHandler.interpret_writer() |> Freer.run()

    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: 9}, outputs: %{writer: [4, 5]}} =
             out
  end

  test "defcon with Error and else handles divide by zero" do
    out = DefconExample.safe_div(10, 0) |> ErrorHandler.interpret_error() |> Freer.run()
    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: :infty}} = out

    out2 = DefconExample.safe_div(10, 2) |> ErrorHandler.interpret_error() |> Freer.run()
    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: 5.0}} = out2
  end
end
