defmodule Freya.Run.RunEffects.CommitOutputs do
  defstruct value: nil, outputs: %{}

  @type t :: %__MODULE__{
          value: any,
          outputs: %{atom => any}
        }
end

defmodule Freya.Run.RunEffects.Constructors do
  alias Freya.Run.RunEffects.CommitOutputs

  @doc """
  A privileged operation which allows delimited effects like
  Error to commit the outputs of a child computation to the
  parent's RunState
  """
  def commit_outputs(value, outputs), do: %CommitOutputs{value: value, outputs: outputs}
end

defmodule Freya.Run.RunEffects do
  @moduledoc "Operations for the core interpreter"
  use Freya.Freer.Ops, constructors: Freya.Run.RunEffects.Constructors
end
