defmodule Freya.Freer.OkResult do
  defstruct value: nil
end

defimpl Freya.Result, for: OkResult do
  def type(_r), do: OkResult
  def value(r), do: r.value
end
