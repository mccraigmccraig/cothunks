defmodule Thunks.Freer do
  @moduledoc """
  A Freer Monad with extensible effects, based on the paper:
  https://okmij.org/ftp/Haskell/extensible/more.pdf

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  https://github.com/bootstarted/effects
  """
  require Logger

  alias Thunks.Freer

  @doc """
  con - profitable cheating - and `with` in Spanish
  """
  defmacro con(mod_or_mods, do: body) do
    imports = expand_imports(mod_or_mods)

    quote do
      unquote_splicing(imports)
      unquote(Macro.postwalk(body, &steps/1))
    end
  end

  defp expand_imports(mods) when is_list(mods) do
    mods
    |> Enum.map(fn mod ->
      quote do
        import unquote(mod)
      end
    end)
  end

  defp expand_imports(mod) do
    expand_imports([mod])
  end

  defp steps({:steps, ctx, [{:<-, _ctx, [lhs, rhs]} | exprs]}) do
    binder(lhs, rhs, steps({:steps, ctx, exprs}))
  end

  defp steps({:steps, _ctx, [[do: expr] | []]}) do
    quote do
      unquote(expr)
    end
  end

  defp steps({:steps, ctx, [expr | exprs]}) do
    binder(
      quote do
        _
      end,
      expr,
      steps({:steps, ctx, exprs})
    )
  end

  defp steps(x), do: x

  defp binder(lhs, rhs, body) do
    quote do
      unquote(rhs)
      |> Freer.bind(fn unquote(lhs) -> unquote(body) end)
    end
  end

  # Freer values are %Pure{} and %Impure{}

  defmodule Pure do
    defstruct val: nil
  end

  defmodule Impure do
    defstruct eff: nil, mval: nil, q: []
  end

  # now the Freer functions

  def pure(x), do: %Pure{val: x}

  def etaf(fa, eff), do: %Impure{eff: eff, mval: fa, q: [&Freer.pure/1]}

  def return(x), do: pure(x)

  def bind(%Pure{val: x}, k), do: k.(x)
  def bind(%Impure{eff: eff, mval: u, q: q}, k), do: %Impure{eff: eff, mval: u, q: q_append(q, k)}

  def q_append(q, mf) do
    Enum.concat(q, [mf])
  end

  def q_concat(qa, qb) do
    Enum.concat(qa, qb)
  end

  @doc """
  apply value `x` to a queue `q` of continuations, returning a Freer value
  """
  def q_apply(q, x) do
    case q do
      [f] -> f.(x)
      [f | t] -> bindp(f.(x), t)
    end
  end

  @doc """
  bind continuation queue `k` to Freer value `mx`, returning a new `Freer` value
  with the continuatino queues concatenated
  """
  def bindp(mx, k) do
    case mx do
      %Pure{val: y} ->
        # Logger.warning("Pure binding: #{inspect(y)}")

        q_apply(k, y)

      %Impure{eff: eff, mval: u, q: q} ->
        # Logger.warning("Impure binding: #{inspect(u)}")

        %Impure{eff: eff, mval: u, q: q_concat(q, k)}
    end
  end

  @doc """
  return a new contiuation ``x->Freer`` which composes the
  continuation `h` onto the queue of continuations `g`
  """
  def q_comp(g, h) do
    fn x ->
      q_apply(g, x) |> h.()
    end
  end

  @doc """
  Aloows easy implementation of interpreters with `ret` and `h` functions

  handle_relay must return a Freer struct
  """
  def handle_relay(%Pure{val: x}, _effs, ret, _h) do
    # Logger.warning("returning: #{inspect(x)}")
    ret.(x)
  end

  def handle_relay(%Impure{eff: eff, mval: u, q: q}, effs, ret, h) do
    # a continuation including this handler
    k = q_comp(q, &handle_relay(&1, effs, ret, h))

    if Enum.member?(effs, eff) do
      # Logger.warning("handling: #{inspect(u)}")
      # we can handle this effect
      h.(u, k)
    else
      # Logger.warning("NOT handling: #{inspect(u)}")
      # we can't handle this particular effect, just update the continuation
      # with this handler
      %Impure{eff: eff, mval: u, q: [k]}
    end
  end

  @doc """
  after all effects are handled, only %Pure{} is left
  """
  def run(%Pure{val: x}), do: x

  def run(%Impure{eff: eff, mval: _u, q: _q} = impure) do
    raise "unhandled effect: #{eff} - #{inspect(impure)}"
  end
end

# TODO
# - some scoped effects
#   - error
#   - coroutine / yield+resume
#   - syntax for scoped effects ?
# - a testing approach
#   - helpers for creating test handlers
#   - and fuzzing/property-based-testing help
