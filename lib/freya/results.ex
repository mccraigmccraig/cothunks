defmodule Freya.OkResult do
  @moduledoc """
  Result type for a finished computation
  """
  defstruct value: nil

  @type t :: %__MODULE__{value: any}

  def ok(val), do: %__MODULE__{value: val}
end

defimpl Freya.Protocols.Result, for: Freya.OkResult do
  def type(_r), do: Freya.OkResult
  def value(r), do: r.value
  def short_circuits?(_r), do: false
end

defmodule Freya.ErrorResult do
  @moduledoc """
  Result type for a computation which is short-circuiting with an error
  """
  defstruct error: nil

  @type t :: %__MODULE__{error: any}

  def error(err), do: %__MODULE__{error: err}
end

defimpl Freya.Protocols.Result, for: Freya.ErrorResult do
  def type(_r), do: Freya.ErrorResult
  def value(r), do: r.error
  def short_circuits?(_r), do: true
end

defmodule Freya.SuspendResult do
  @moduledoc """
  Result type for a computation which is yielding a value to a caller,
  with the expectation that the caller will supply a return value to
  continue the computation
  """
  defstruct value: nil, continuation: nil

  @type t :: %__MODULE__{value: any, continuation: (any -> any)}

  def yield(val, continuation),
    do: %__MODULE__{value: val, continuation: continuation}
end

defimpl Freya.Protocols.Result, for: Freya.SuspendResult do
  def type(_r), do: Freya.SuspendResult
  def value(r), do: r.value
  def short_circuits?(_r), do: true
end

# default implementation allows us to detect non-Result values
defimpl Freya.Protocols.Result, for: Any do
  def type(_r), do: nil
  def value(r), do: r
  def short_circuits?(_r), do: false
end

defmodule Freya.Result do
  alias Freya.OkResult
  alias Freya.ErrorResult
  alias Freya.SuspendResult

  @type result :: OkResult.t() | ErrorResult.t() | SuspendResult.t()
end
