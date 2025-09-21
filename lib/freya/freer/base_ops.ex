defmodule Freya.Freer.BaseOps do
  @moduledoc """
  Functions in this module will always be imported into
  Freer.con blocks
  """
  def return(x), do: Freya.Freer.return(x)
end
