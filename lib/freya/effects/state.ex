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
  alias Freya.Freer.Pure
  alias Freya.Effects.State
  alias Freya.Run.RunState

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == State
  end

  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: eff, data: u, q: q} = _computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    case {eff, u} do
      {State, {:put, o}} ->
        {Impl.q_apply(q, nil), o}

      {State, :get} ->
        {Impl.q_apply(q, state), state}

      _ ->
        {%Freer.Impure{sig: eff, data: u, q: q}, state}
    end
  end

  @impl Freya.EffectHandler
  def finalize(
        %Pure{} = computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    {computation, state}
  end
end
