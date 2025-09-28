defmodule Freya.Effects.State.Constructors do
  @moduledoc "Constructors for the State effect"

  def put(o), do: {:put, o}
  def get(), do: :get
end

defmodule Freya.Effects.State do
  @moduledoc "Operations (Ops) for the State effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.State.Constructors
end

defmodule Freya.Effects.State.Interpreter do
  @moduledoc """
  A State effect implementation using the Freer monad.
  """

  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Effects.State

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == State
  end

  @impl Freya.EffectHandler
  def interpret(computation, _handler_key, state, _all_states) do
    case computation do
      %Freer.Pure{val: _x} = pure ->
        {pure, state}

      %Freer.Impure{sig: eff, data: u, q: q} ->
        case {eff, u} do
          {State, {:put, o}} ->
            {Impl.q_apply(q, nil), o}

          {State, :get} ->
            {Impl.q_apply(q, state), state}

          _ ->
            {%Freer.Impure{sig: eff, data: u, q: q}, state}
        end
    end
  end
end
