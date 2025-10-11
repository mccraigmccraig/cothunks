defmodule Freya.Effects.State do
  @moduledoc """
  Operations in the State effect
  """

  defmodule Get do
    use Freya.Effect.SendableImpl, sig: Freya.Effects.State
    defstruct []
  end

  defmodule Put do
    use Freya.Effect.SendableImpl, sig: Freya.Effects.State
    defstruct val: nil
  end

  def put(v), do: %Put{val: v}
  def get, do: %Get{}
end

defmodule Freya.Effects.State.Handler do
  @moduledoc """
  A State effect implementation using the Freer monad.
  """

  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Effects.State
  alias Freya.Effects.State.Get
  alias Freya.Effects.State.Put
  alias Freya.Run.RunState

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == State
  end

  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: State, data: u, q: q} = _computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    case u do
      %Put{val: o} ->
        # return the old value, set the new
        {Impl.q_apply(q, state), o}

      %Get{} ->
        {Impl.q_apply(q, state), state}
    end
  end
end
