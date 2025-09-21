defmodule Freya.Freer.YieldResult do
  defstruct value: nil, continuation: nil
end

defimpl Freya.Result, for: Freya.Freer.YieldResult do
  def type(_r), do: Freya.Freer.YieldResult
  def value(r), do: r.value
end
