defmodule Freya.Effect.SendableImpl do
  defmacro __using__(opts) do
    sig = Keyword.get(opts, :sig)

    quote do
      defimpl Freya.Protocols.Sendable, for: __MODULE__ do
        def send(eff),
          do: Freya.Freer.send_effect(eff, unquote(sig))
      end
    end
  end
end
