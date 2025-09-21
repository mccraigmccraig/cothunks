defmodule Freya.Freer.ErrorResult do
  defstruct error: nil
end

defimpl Freya.Result, for: ErrorResult do
  def type(_r), do: ErrorResult
  def value(r), do: r.error
end
