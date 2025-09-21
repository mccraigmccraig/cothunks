defmodule Freya.RunOutcome do
  @moduledoc """
  Unified run outcome envelope for Freya interpreters.

  - `result`: the primary computation value
  - `outputs`: flat map for effect-specific outputs (e.g., state, writer, logs)
  """

  defstruct result: nil, outputs: %{}

  @type t :: %__MODULE__{result: any, outputs: map()}

  @spec new(any, map()) :: t
  def new(result, outputs \\ %{}) when is_map(outputs), do: %__MODULE__{result: result, outputs: outputs}

  @spec ensure(any) :: t
  def ensure(%__MODULE__{} = r), do: r
  def ensure(result), do: new(result)

  @spec put(t, atom, any) :: t
  def put(%__MODULE__{outputs: out} = r, key, val) when is_atom(key) do
    %{r | outputs: Map.put(out, key, val)}
  end

  @spec merge(t, map()) :: t
  def merge(%__MODULE__{outputs: out} = r, m) when is_map(m) do
    %{r | outputs: Map.merge(out, m)}
  end

  @spec value(t) :: any
  def value(%__MODULE__{result: v}), do: v

  @spec outputs(t) :: map()
  def outputs(%__MODULE__{outputs: out}), do: out
end
