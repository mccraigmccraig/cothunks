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
      _ <- put(a)
      _ <- put(b)
      return(a + b)
    end

    def call_private(a, b) do
      write_and_sum(a, b)
    end

    Freer.defcon safe_div(a, b), [Error] do
      if b == 0 do
        Error.throw_fx(:zero)
      else
        return(a / b)
      end
    else
      :zero -> return(:infty)
    end

    Freer.defcon sum_and_log(a, b), [Reader, Writer] do
      s <- DefconExample.sum_env(a, b)
      _ <- Writer.put({:sum, s})
      return(s)
    end

    Freer.defcon sum_twice(a, b), [Reader] do
      x <- DefconExample.sum_env(a, b)
      y <- DefconExample.sum_env(x, 0)
      return(y)
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

defmodule Freya.DefconCompositionTest do
  use ExUnit.Case
  alias Freya.Freer
  alias Freya.Effects.{ReaderHandler, WriterHandler}

  test "defcon composition: sum_and_log composes Reader and Writer and calls another defcon" do
    out =
      Freya.DefconTest.DefconExample.sum_and_log(1, 2)
      |> ReaderHandler.interpret_reader(3)
      |> WriterHandler.interpret_writer()
      |> Freer.run()

    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: 6}, outputs: %{writer: [{:sum, 6}]}} = out
  end

  test "defcon composition: sum_twice calls another defcon twice" do
    out =
      Freya.DefconTest.DefconExample.sum_twice(1, 2)
      |> ReaderHandler.interpret_reader(3)
      |> Freer.run()

    # First sum_env: 1+2+3 = 6; second: 6+0+3 = 9
    assert %Freya.RunOutcome{result: %Freya.Freer.OkResult{value: 9}} = out
  end
end
