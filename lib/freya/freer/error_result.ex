defmodule Freya.Freer.ErrorResult do
  defstruct error: nil
end

defimpl Freya.Result, for: Freya.Freer.ErrorResult do
  def type(_r), do: Freya.Freer.ErrorResult
  def value(r), do: r.error
end
