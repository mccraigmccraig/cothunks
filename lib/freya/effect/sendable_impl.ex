defmodule Freya.Effect.SendableImpl do
  defmacro __using__(_opts) do
    quote do
      defimpl Freya.Protocols.Sendable, for: __MODULE__ do
        def send(eff),
          do: Freya.Freer.send_effect(eff, Freya.Effects.State)
      end
    end
  end
end
