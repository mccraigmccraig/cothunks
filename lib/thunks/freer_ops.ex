defmodule Thunks.FreerOps do
  @moduledoc """
  wrap all the data-constructors in a provided module
  with Freer.etaf() - resulting in a module of operations
  for use with Freer
  """
  defmacro __using__(opts) do
    ops_mod_alias = Keyword.get(opts, :ops)
    ops_mod = Macro.expand(ops_mod_alias, __CALLER__)
    # Logger.error("ops_mod: #{inspect(ops_mod)}")
    functions = ops_mod.__info__(:functions)
    # Logger.error("functions: #{inspect(functions)}")

    freer_functions =
      functions
      |> Enum.map(fn {f, arity} -> Thunks.FreerOps.freer_op(ops_mod, f, arity) end)

    # Logger.error("FREER_FUNCTIONS\n#{inspect(freer_functions, pretty: true)}")

    quote do
      (unquote_splicing(freer_functions))
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
            apply(unquote(ops_mod), unquote(f_atom), []) |> Thunks.Freer.etaf(__MODULE__)
          end
        end

      1 ->
        quote do
          def unquote(f_atom)(a) do
            apply(unquote(ops_mod), unquote(f_atom), [a]) |> Thunks.Freer.etaf(__MODULE__)
          end
        end

      2 ->
        quote do
          def unquote(f_atom)(a, b) do
            apply(unquote(ops_mod), unquote(f_atom), [a, b])
            |> Thunks.Freer.etaf(__MODULE__)
          end
        end

      3 ->
        quote do
          def unquote(f_atom)(a, b, c) do
            apply(unquote(ops_mod), unquote(f_atom), [a, b, c])
            |> Thunks.Freer.etaf(__MODULE__)
          end
        end

      4 ->
        quote do
          def unquote(f_atom)(a, b, c, d) do
            apply(unquote(ops_mod), unquote(f_atom), [a, b, c, d])
            |> Thunks.Freer.etaf(__MODULE__)
          end
        end
    end
  end
end
