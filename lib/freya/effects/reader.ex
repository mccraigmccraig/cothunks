defmodule Freya.Effects.Reader.Constructors do
  @moduledoc "Constructors for the Reader effect"

  @doc "Get the current environment value"
  def ask(), do: :ask
end

defmodule Freya.Effects.Reader do
  @moduledoc "Operations (Ops) for the Reader effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Reader.Constructors
end

defmodule Freya.Effects.Reader.Interpreter do
  @moduledoc "Interpreter (handler) for the Reader effect"
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Effects.Reader

  @behaviour Freya.EffectHandler

  @impl true
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Reader
  end

  @impl true
  def interpret(computation, _handler_key, state, _all_states) do
    case computation do
      %Freer.Pure{val: _x} = pure ->
        {pure, state}

      %Freer.Impure{sig: eff, data: u, q: q} ->
        case {eff, u} do
          {Reader, :ask} ->
            {Impl.q_apply(q, state), state}

          _ ->
            {%Freer.Impure{sig: eff, data: u, q: q}, state}
        end
    end
  end
end
