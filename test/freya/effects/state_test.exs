defmodule Freya.Effects.StateTest do
  use ExUnit.Case

  require Logger

  import Freya.Con

  alias Freya.Effects.EffectLogger
  alias Freya.Effects.Reader
  alias Freya.Effects.State
  alias Freya.Effects.Writer
  alias Freya.Run

  defcon calc(v), [Reader, Writer, State] do
    a <- ask()
    b <- get()
    c <- return(v)
    _ <- put(a * b * c)
    tell(a + b + c)
    return(a * b * c)
  end

  describe "simple state" do
    test "it does state stuff" do
      runner =
        Run.with_handlers(
          l: EffectLogger.Interpreter,
          s: {State.Interpreter, 5},
          r: {Reader.Interpreter, 7},
          w: {Writer.Interpreter, []}
        )

      outcome = Run.run(calc(10), runner)

      assert outcome.result == %Freya.Freer.OkResult{value: 350}

      Logger.error("#{__MODULE__}.outcome\n" <> inspect(outcome, pretty: true))
      # assert outcome == nil
    end
  end
end
