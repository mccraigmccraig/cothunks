defmodule Freya.Run.RunEffects.CommitOutputs do
  defstruct value: nil, states: %{}

  @type t :: %__MODULE__{
          value: any,
          states: %{atom => any}
        }
end

defmodule Freya.Run.RunEffects.Constructors do
  alias Freya.Run.RunEffects.CommitOutputs

  @doc """
  A privileged operation which allows delimited effects like
  Error to commit the effect states of a child computation to the
  parent's RunState
  """
  def commit_states(value, states), do: %CommitOutputs{value: value, states: states}
end

defmodule Freya.Run.RunEffects do
  @moduledoc "Operations for the core interpreter"
  use Freya.Freer.Ops, constructors: Freya.Run.RunEffects.Constructors
end
