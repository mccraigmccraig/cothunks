defmodule Freya.Sig.DefEffectStruct do
  defmacro def_effect_struct(mod, struct_args \\ []) do
    sig = __CALLER__.module

    quote do
      defmodule unquote(mod) do
        use Freya.Sig.Sendable, sig: unquote(sig)
        defstruct unquote(struct_args)
      end
    end
  end
end
