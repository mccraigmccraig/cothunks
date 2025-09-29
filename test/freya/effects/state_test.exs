defmodule Freya.Effects.StateTest do
  use ExUnit.Case

  alias Freya.Effects.EffectLogger
  alias Freya.Effects.Reader
  alias Freya.Effects.State
  alias Freya.Effects.Writer
  alias Freya.Freer
  alias Freya.Run

  describe "simple state" do
    test "it does state stuff" do
      require Freer
      import Freya.Con

      computation =
        con [Reader, Writer, State] do
          a <- ask()
          b <- get()
          c <- return(10)
          _ <- put(a * b * c)
          tell(a + b + c)
          return(a * b * c)
        end

      runner =
        Run.with_handlers(
          l: EffectLogger.Interpreter,
          s: {State.Interpreter, 5},
          r: {Reader.Interpreter, 7},
          w: {Writer.Interpreter, []}
        )

      outcome = Run.run(computation, runner)

      assert outcome == nil
    end
  end
end
