defmodule Freya.Freer.OkResult do
  @moduledoc """
  Result type for a finished computation
  """
  defstruct value: nil
end

defimpl Freya.Result, for: Freya.Freer.OkResult do
  def type(_r), do: Freya.Freer.OkResult
  def value(r), do: r.value
end

defmodule Freya.Freer.ErrorResult do
  @moduledoc """
  Result type for a computation which is short-circuiting with an error
  """
  defstruct error: nil
end

defimpl Freya.Result, for: Freya.Freer.ErrorResult do
  def type(_r), do: Freya.Freer.ErrorResult
  def value(r), do: r.error
end

defmodule Freya.Freer.YieldResult do
  @moduledoc """
  Result type for a computation which is yielding a value to a caller,
  with the expectation that the caller will supply a return value to
  continue the computation
  """
  defstruct value: nil, continuation: nil
end

defimpl Freya.Result, for: Freya.Freer.YieldResult do
  def type(_r), do: Freya.Freer.YieldResult
  def value(r), do: r.value
end
