defmodule Freya.Freer.OkResult do
  defstruct value: nil
end

defimpl Freya.Result, for: Freya.Freer.OkResult do
  def type(_r), do: Freya.Freer.OkResult
  def value(r), do: r.value
end
