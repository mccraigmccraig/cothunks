defmodule Freya.Run.RunEffects.ScopedResult do
  alias Freya.RunOutcome
  alias Freya.Freer

  defstruct computation: nil, run_outcome: nil

  @type t :: %__MODULE__{
          computation: Freer.freer(),
          run_outcome: RunOutcome.t()
        }
end

defimpl Freya.Protocols.Sendable, for: Freya.Run.RunEffects.ScopedResult do
  def send(%Freya.Run.RunEffects.ScopedResult{} = eff),
    do: Freya.Freer.send_effect(eff, Freya.Run.RunEffects)
end

defmodule Freya.Run.RunEffects do
  alias Freya.Run.RunEffects.ScopedResult

  @doc """
  A privileged operation which allows scoped effects like
  Error to return the effect states of a child computation to the
  parent's RunState, along with a computation to continue with

  NB: this is a privileged operation which can't be handled in
  a normal EffectHandler and must be handled in Run - because it
  can involve modification of any EffectHandler's state, not just the
  EffectHandler's own state
  """
  def scoped_result(computation, run_outcome),
    do: %ScopedResult{computation: computation, run_outcome: run_outcome}
end
