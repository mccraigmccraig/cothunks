defmodule Freya.Freer.YieldResult do
  defstruct value: nil
end

defimpl Freya.Result, for: YieldResult do
  def type(_r), do: YieldResult
  def value(r), do: r.value
end
