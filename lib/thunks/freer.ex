defmodule Thunks.Freer do
  @moduledoc """
  A Freer Monad, based on the Haskell from:
  https://okmij.org/ftp/Computation/free-monad.html

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  """
  require Logger

  alias Thunks.Freer

  @doc """
  con - profitable cheating - and `with` in Spanish
  """
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

  def freer_op(ops_mod, f_atom, arity) do
    # haven't managed to get the arg-quoting right on an any-arity version
    # of this macro
    # args =
    #   Range.new(0, arity - 1, 1)
    #   |> Enum.map(fn i -> "arg_#{i}" |> String.to_atom() end)
    #   |> Enum.map(fn i -> var!(i) end)

    case arity do
      0 ->
        quote do
          def unquote(f_atom)() do
            apply(unquote(ops_mod), unquote(f_atom), []) |> Freer.etaf()
          end
        end

      1 ->
        quote do
          def unquote(f_atom)(a) do
            apply(unquote(ops_mod), unquote(f_atom), [a]) |> Freer.etaf()
          end
        end

      2 ->
        quote do
          def unquote(f_atom)(a, b) do
            apply(unquote(ops_mod), unquote(f_atom), [a, b]) |> Freer.etaf()
          end
        end
    end
  end

  defmodule FreerOps do
    defmacro __using__(opts) do
      ops_mod_alias = Keyword.get(opts, :ops)
      ops_mod = Macro.expand(ops_mod_alias, __CALLER__)
      Logger.error("ops_mod: #{inspect(ops_mod)}")
      functions = ops_mod.__info__(:functions)
      Logger.error("functions: #{inspect(functions)}")

      freer_functions =
        functions
        |> Enum.map(fn {f, arity} -> Freer.freer_op(ops_mod, f, arity) end)

      Logger.error("FREER_FUNCTIONS\n#{inspect(freer_functions, pretty: true)}")

      quote do
        (unquote_splicing(freer_functions))
      end
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
    # how about... stick with the freer monad, with
    # a simple-data langauge and interpreted effects...
    # the add logging into the interpretation
    # - return logged values on retry/resume
    # - return resumed value on yield
    # &c
    # or maybe logging &c is just another layer inside freer...
    # forget about thunks - all about the data ?
    # hmmm.... thought required
    #
    # macro to compiles a delegation module for operations
    # modules, which does the op-function -> etaf wrapping
    #
    # defoperations(MODULE, language_module)
    #
    # maybe create a signature struct/structs for the operations
    # of a langauge - so we can dynamically check results
    f = fn x -> x |> q.() |> interpret(unit_f, bind_f) end
    bind_f.(m, f)
  end

  def interpreter(unit_f, bind_f) do
    fn freer -> interpret(freer, unit_f, bind_f) end
  end
end
