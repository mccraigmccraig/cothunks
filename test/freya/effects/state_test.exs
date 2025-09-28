defmodule Freya.Effects.StateTest do
  use ExUnit.Case

  alias Freya.Effects.Reader
  alias Freya.Effects.Writer
  alias Freya.Effects.State.StateExpanded
  alias Freya.Freer
  alias Freya.Run

  describe "simple state" do
    test "it does state stuff" do
      require Freer
      import Freya.Con

      computation =
        con [Reader, Writer] do
          a <- get()
          _ <- put(a * 10)
          b <- get()
          return(a + b)
        end

      runner = Run.with_handlers(s: {StateExpanded, 5})

      outcome = Run.run(computation, runner)

      assert outcome == nil
    end
  end
end
