defmodule Freya.Run.RunEffects.CommitStates do
  alias Freya.RunOutcome

  defstruct value: nil, run_outcome: nil

  @type t :: %__MODULE__{
          value: any,
          run_outcome: RunOutcome.t()
        }
end

defimpl Freya.Protocols.Sendable, for: Freya.Run.RunEffects.CommitStates do
  def send(%Freya.Run.RunEffects.CommitStates{} = eff),
    do: Freya.Freer.send_effect(eff, Freya.Run.RunEffects)
end

defmodule Freya.Run.RunEffects.DiscardStates do
  alias Freya.RunOutcome

  defstruct value: nil, run_outcome: nil

  @type t :: %__MODULE__{
          value: any,
          run_outcome: RunOutcome.t()
        }
end

defimpl Freya.Protocols.Sendable, for: Freya.Run.RunEffects.DiscardStates do
  def send(%Freya.Run.RunEffects.DiscardStates{} = eff),
    do: Freya.Freer.send_effect(eff, Freya.Run.RunEffects)
end

defmodule Freya.Run.RunEffects do
  alias Freya.Run.RunEffects.CommitStates
  alias Freya.Run.RunEffects.DiscardStates

  @doc """
  A privileged operation which allows delimited effects like
  Error to commit the effect states of a child computation to the
  parent's RunState
  """
  def commit(value, run_outcome), do: %CommitStates{value: value, run_outcome: run_outcome}

  @doc """
  A privileged operation which allows delimited effects like
  Error to discard the effect states of a child computation
  """
  def discard(value, run_outcome), do: %DiscardStates{value: value, run_outcome: run_outcome}
end

defmodule Freya.Run.RunEffects.Handler do
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Run.RunEffects
  alias Freya.Run.RunEffects.CommitStates
  alias Freya.Run.RunEffects.DiscardStates
  alias Freya.Run.RunState

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == RunEffects
  end

  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: RunEffects, data: u, q: q} = _computation,
        _handler_key,
        _state,
        %RunState{} = run_state
      ) do
    case u do
      %CommitStates{value: value, run_outcome: run_outcome} ->
        {Impl.q_apply(q, value), %{run_state | states: run_outcome.run_state.states}}

      %DiscardStates{value: value, run_outcome: _run_outcome} ->
        {Impl.q_apply(q, value), run_state}
    end
  end
end
