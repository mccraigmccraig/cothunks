defmodule Freya.Sig.Sendable do
  defmacro __using__(opts) do
    sig = Keyword.get(opts, :sig)

    quote do
      defimpl Freya.Sig.ISendable, for: __MODULE__ do
        def send(eff),
          do: Freya.Freer.send_effect(eff, unquote(sig))
      end
    end
  end
end
