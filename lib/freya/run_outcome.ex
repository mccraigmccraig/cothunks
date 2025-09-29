defmodule Freya.RunOutcome do
  @moduledoc """
  Unified run outcome envelope for Freya interpreters.

  - `result`: the primary computation value
  - `outputs`: flat map for effect-specific outputs (e.g., state, writer, logs)
  """

  defstruct result: nil, outputs: %{}

  @type t :: %__MODULE__{result: any, outputs: map()}

  @spec new(any, map()) :: t
  def new(result, outputs) when is_map(outputs),
    do: %__MODULE__{result: result, outputs: outputs}
end
