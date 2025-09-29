defmodule Freya.RunOutcome do
  @moduledoc """
  Unified run outcome envelope for Freya interpreters.

  - `result`: the primary computation value
  - `outputs`: flat map for effect-specific outputs (e.g., state, writer, logs)
  """

  defstruct result: nil, outputs: %{}

  @type t :: %__MODULE__{result: any, outputs: map()}

  @spec new(any, map()) :: t
  def new(result, outputs \\ %{}) when is_map(outputs),
    do: %__MODULE__{result: result, outputs: outputs}

  @doc """
  Ensure value is a RunOutcome. Idempotent: returns a RunOutcome unchanged,
  or wraps a raw value as an OkResult outcome.
  Intended for interpreter ret functions; callers should use ok/error/yield explicitly.
  """
  @spec ensure(any) :: t
  def ensure(%__MODULE__{} = r), do: r
  def ensure(value), do: ok(value)

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

  @doc "Create an Ok outcome containing a value"
  @spec ok(any) :: t
  def ok(%__MODULE__{} = r), do: r
  def ok(value), do: new(%Freya.OkResult{value: value})

  @doc "Create an Error outcome containing an error"
  @spec error(any) :: t
  def error(error), do: new(%Freya.ErrorResult{error: error})

  @doc "Create a Yield outcome containing a value and continuation"
  @spec yield(any, (any -> any)) :: t
  def yield(value, continuation) when is_function(continuation, 1) do
    new(%Freya.YieldResult{value: value, continuation: continuation})
  end

  @doc "Return the result variant type for a RunOutcome"
  @spec result_type(t) :: atom
  def result_type(%__MODULE__{result: r}), do: Freya.Protocols.Result.type(r)

  @doc "Return the payload value for a RunOutcome's result"
  @spec result_value(t) :: any
  def result_value(%__MODULE__{result: r}), do: Freya.Protocols.Result.value(r)

  @doc """
  Flatten nested RunOutcome within OkResult payloads by merging outputs upward.
  Useful when interpreter composition accidentally nests outcomes.
  """
  @spec flatten(t) :: t
  def flatten(%__MODULE__{
        result: %Freya.OkResult{value: %__MODULE__{} = inner},
        outputs: out
      }) do
    merged = %__MODULE__{result: inner.result, outputs: Map.merge(inner.outputs, out)}
    flatten(merged)
  end

  def flatten(%__MODULE__{} = r), do: r
end
