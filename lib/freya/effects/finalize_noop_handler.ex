defmodule Freya.Effects.FinalizeNoopHandler do
  @moduledoc """
  Default no-op handler for the Finalize effect.
  Consumes Finalize by returning the carried RunOutcome unchanged.
  """

  alias Freya.Freer

  @doc "Interpret Finalize by returning the payload outcome without changes"
  def interpret(computation) do
    Freya.Freer.Impl.handle_relay(
      computation,
      [Freya.Effects.Finalize],
      fn x -> Freya.RunOutcome.ensure(x) |> Freer.return() end,
      fn {:finalize, %Freya.RunOutcome{} = out}, _k -> Freer.return(out) end
    )
  end
end

