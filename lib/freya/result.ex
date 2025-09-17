defmodule Freya.Result do
  @moduledoc """
  Unified result envelope for Freya interpreters.

  - `value`: the primary computation value
  - `outputs`: flat map for effect-specific outputs (e.g., state, writer, logs)
  """

  defstruct value: nil, outputs: %{}

  @type t :: %__MODULE__{value: any, outputs: map()}

  @spec new(any, map()) :: t
  def new(value, outputs \\ %{}) when is_map(outputs), do: %__MODULE__{value: value, outputs: outputs}

  @spec ensure(any) :: t
  def ensure(%__MODULE__{} = r), do: r
  def ensure(value), do: new(value)

  @spec put(t, atom, any) :: t
  def put(%__MODULE__{outputs: out} = r, key, val) when is_atom(key) do
    %{r | outputs: Map.put(out, key, val)}
  end

  @spec merge(t, map()) :: t
  def merge(%__MODULE__{outputs: out} = r, m) when is_map(m) do
    %{r | outputs: Map.merge(out, m)}
  end

  @spec value(t) :: any
  def value(%__MODULE__{value: v}), do: v

  @spec outputs(t) :: map()
  def outputs(%__MODULE__{outputs: out}), do: out
end

