defmodule Freya.Run.RunEffects.ScopedResult do
  use Freya.Effect.SendableImpl

  defstruct computation: nil, run_outcome: nil

  @type t :: %__MODULE__{
          computation: Freya.Freer.freer(),
          run_outcome: Freya.RunOutcome.t()
        }
end

defmodule Freya.Run.RunEffects do
  @doc """
  A privileged operation which allows scoped effects like
  Error to return the effect states of a child computation to the
  parent's RunState, along with a computation to continue with

  NB: this is a privileged operation which can't be handled in
  a normal EffectHandler and must be handled in Run - because it
  can involve modification of any EffectHandler's state, not just the
  EffectHandler's own state

  * computation - a Pure or Impure which the scoping handler can use
    to achieve anything (continue, return an error &c) once the
    effect states have been updated
  * run_outcome - the outcome of the scoped computation, including
      the result, the effect states and the effect outputs
  """
  def scoped_result(computation, run_outcome),
    do: %Freya.Run.RunEffects.ScopedResult{
      computation: computation,
      run_outcome: run_outcome
    }
end
