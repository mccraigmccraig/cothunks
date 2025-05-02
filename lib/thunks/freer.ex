defmodule Thunks.Freer do
  @moduledoc """
  A Freer Monad, based on the Haskell from:
  https://okmij.org/ftp/Computation/free-monad.html

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  """
  require Logger

  alias Thunks.Freer

  defmacro con(mod, do: body) do
    quote do
      import unquote(mod)
      unquote(Macro.postwalk(body, &steps/1))
    end
  end

  defp steps({:steps, ctx, [{:<-, _ctx, [lhs, rhs]} | exprs]}) do
    binder(lhs, rhs, steps({:steps, ctx, exprs}))
  end

  defp steps({:steps, _ctx, [[do: expr] | []]}) do
    quote do
      unquote(expr)
    end
  end

  defp steps(x), do: x

  defp binder(lhs, rhs, body) do
    quote do
      unquote(rhs)
      |> Freer.bind(fn unquote(lhs) -> unquote(body) end)
    end
  end

  def pure(x), do: {:pure, x}

  def etaf(fa), do: {:impure, fa, &Freer.pure/1}

  def return(x), do: pure(x)

  def bind({:pure, x}, k), do: k.(x)
  def bind({:impure, u, kp}, k), do: {:impure, u, gtgtgt(kp, k)}

  # >>> in Haskell - composes monadic functions
  # (a -> m b) -> (b -> m c) -> (a -> m c)
  def gtgtgt(mff, mfg), do: fn x -> mff.(x) |> bind(mfg) end

  def interpret({:pure, x}, unit_f, _bind_f), do: unit_f.(x)

  def interpret({:impure, m, q}, unit_f, bind_f) do
    f = fn x -> x |> q.() |> interpret(unit_f, bind_f) end
    bind_f.(m, f)
  end

  def interpreter(unit_f, bind_f) do
    fn freer -> interpret(freer, unit_f, bind_f) end
  end
end
