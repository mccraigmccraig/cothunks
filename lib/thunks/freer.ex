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

  @type freer() :: %Pure{} | %Impure{}

  defp freer?(%Pure{}), do: true
  defp freer?(%Impure{}), do: true
  defp freer?(_), do: false

  # now the Freer functions

  @spec pure(any) :: freer
  def pure(x), do: %Pure{val: x}

  @spec send(any, atom) :: freer
  def send(fa, eff) do
    Logger.info("send: #{inspect(fa)}, #{inspect(eff)}")
    %Impure{eff: eff, mval: fa, q: [&Freer.pure/1]}
  end

  @spec return(any) :: freer
  def return(x), do: pure(x)

  @spec bind(freer, (any -> freer)) :: freer
  def bind(%Pure{val: x}, k), do: k.(x)
  def bind(%Impure{eff: eff, mval: u, q: q}, k), do: %Impure{eff: eff, mval: u, q: q_append(q, k)}

  @doc """
  add a continuation `mf` to a queue of continuations `q`
  """
  @spec q_append([(any -> freer)], (any -> freer)) :: [(any -> freer)]
  def q_append(q, mf) do
    Enum.concat(q, [mf])
  end

  @doc """
  concatenate two queues of continuations
  """
  @spec q_concat([(any -> freer)], [(any -> freer)]) :: [(any -> freer)]
  def q_concat(qa, qb) do
    Enum.concat(qa, qb)
  end

  @doc """
  apply value `x` to a queue `q` of continuations, returning a Freer value

  applies a value throught the list of continuations until it gets an %Impure{}
  result, then adds any remaining continuations from `q` to the queue of
  that %Impure{}
  """
  @spec q_apply([(any -> freer)], any) :: freer
  def q_apply(q, x) do
    Logger.info("apply: #{inspect(x)}")

    case q do
      [k] -> k.(x)
      [k | t] -> bindp(k.(x), t)
    end
  end

  @doc """
  bind continuation queue `k` to Freer value `mx`, returning a new `Freer` value
  with the continuation queues concatenated
  """
  @spec bindp(freer, [(any -> freer)]) :: freer
  def bindp(mx, k) do
    case mx do
      %Pure{val: y} ->
        # Logger.warning("Pure apply: #{inspect(y)}")

        q_apply(k, y)

      %Impure{eff: eff, mval: u, q: q} ->
        # Logger.warning("Impure apply: #{inspect(u)}")

        %Impure{eff: eff, mval: u, q: q_concat(q, k)}
    end
  end

  @doc """
  return a new contiuation `x->Freer` which composes the
  `(freer -> freer)` function `h` with the _application_ of the
  queue of continuations `g`
  """
  @spec q_comp([(any -> freer)], (freer -> freer)) :: (any -> freer)
  def q_comp(g, h) do
    fn x ->
      q_apply(g, x) |> h.()
    end
  end

  @doc """
  Aloows easy implementation of interpreters with `ret` and `h` functions

  handle_relay must return a Freer struct
  """
  @spec handle_relay(freer, [atom], (any -> freer), (any, (any -> freer) -> freer)) :: freer
  def handle_relay(%Pure{val: x}, _effs, ret, _h) do
    # Logger.warning("handle %Pure{}: #{inspect(x)}")
    ret.(x)
  end

  def handle_relay(%Impure{eff: eff, mval: u, q: q}, effs, ret, h) do
    # a continuation including this handler
    k = q_comp(q, &handle_relay(&1, effs, ret, h))

    if Enum.member?(effs, eff) do
      # Logger.warning("handle %Impure{}: #{inspect(u)}")
      # we can handle this effect
      h.(u, k)
    else
      # Logger.warning("NOT handling %Impure{}: #{inspect(u)}")
      # we can't handle this particular effect, just update the continuation
      # with this handler
      %Impure{eff: eff, mval: u, q: [k]}
    end
  end

  @doc """
  Allows easy implementation of interpreters which maintain state - such as the
  classical State effect. Adapted from the freer-simple implementation
  """
  @spec handle_relay_s(freer, [atom], any, (any -> freer), (any, (any -> freer) -> freer)) ::
          freer
  def handle_relay_s(%Pure{val: x}, _effs, initial_state, ret, _h) do
    ret.(initial_state).(x)
  end

  def handle_relay_s(%Impure{eff: eff, mval: u, q: q}, effs, initial_state, ret, h) do
    # a continuation including this handler
    k = fn s -> q_comp(q, &handle_relay_s(&1, effs, s, ret, h)) end

    if Enum.member?(effs, eff) do
      # Logger.warning("handle %Impure{}: #{inspect(u)}")
      # we can handle this effect
      h.(initial_state).(u, k)
    else
      # Logger.warning("NOT handling %Impure{}: #{inspect(u)}")
      # we can't handle this particular effect, just update the continuation
      # with this handler
      %Impure{eff: eff, mval: u, q: [k.(initial_state)]}
    end
  end

  @doc """
  after all effects are handled, only %Pure{} is left
  """
  @spec run(freer) :: any
  def run(%Pure{val: x}), do: x

  def run(%Impure{eff: eff, mval: _u, q: _q} = impure) do
    raise "unhandled effect: #{eff} - #{inspect(impure)}"
  end

  ###############################
  #

  # trying out a handler which just logs and passes on
  # to the next handler... maybe we could use such a handler
  # to implement log/resume ?
  def handle_all(%Freer.Pure{} = pure_val) do
    Logger.warning("handle_all: #{inspect(pure_val)}")
    pure_val
  end

  def handle_all(%Freer.Impure{eff: eff, mval: u, q: q} = impure_val) do
    Logger.warning("handle_all: #{inspect(impure_val)}")

    # a continuation including this handler
    k = Freer.q_comp(q, &handle_all(&1))

    %Freer.Impure{eff: eff, mval: u, q: [k]}
  end
end

# TODO
# - some scoped effects
#   - error
#   - JSON serialisation of steps
#     - each continuation in a queue is a step
#     - we can capture inputs and outputs
#   - syntax for scoped effects ?
# - a testing approach
#   - helpers for creating test handlers
#   - and fuzzing/property-based-testing help
# - can we construct a log/resume handler ?
#   - a handler which records a de/seriializable statement/result log,
#     and if there's already a log, and the statements match then
#     short-circuits and returns the result directly
#   - imposes the constraint that statements/results must be de/serializable
#   - when "resuming", we must follow the continuation chain sufficienly well
#     that the binds that need to happen (for expressions which aren't
#     completely short-circuited) happen correctly
