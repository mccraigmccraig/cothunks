defmodule Thunks.Freer do
  @moduledoc """
  A Freer Monad, based on the Haskell from:
  https://okmij.org/ftp/Computation/free-monad.html

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  """

  alias Thunks.Freer

  def pure(x), do: {:pure, x}

  def etaf(fa), do: {:impure, fa, &Freer.pure/1}

  def return(x), do: pure(x)

  def bind({:pure, x}, k), do: k.(x)

  def bind({:impure, u, kp}, k), do: {:impure, u, gtgtgt(kp, k)}

  # >>> in Haskell - composes monadic functions
  # (a -> m b) -> (b -> m c) -> (a -> m c)
  def gtgtgt(mff, mfg), do: fn x -> mff.(x) |> bind(mfg) end

  # not yet sure why aemaeth returns a function rather than
  # interprets directly
  def interpret({:pure, x}, unit_f, _bind_f), do: unit_f.(x)

  def interpret({:impure, m, q}, unit_f, bind_f) do
    f = fn x -> x |> q.() |> interpret(unit_f, bind_f) end
    bind_f.(m, f)
  end
end
