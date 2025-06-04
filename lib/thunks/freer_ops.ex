defmodule Thunks.FreerOps do
  @moduledoc """
  wrap all the data-constructors in a provided module
  with Freer.send() - resulting in a module of operations
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
    # Generate argument variables dynamically based on arity
    args =
      for i <- 0..(arity - 1)//1 do
        {String.to_atom("arg_#{i}"), [], Elixir}
      end

    quote do
      def unquote(f_atom)(unquote_splicing(args)) do
        apply(unquote(ops_mod), unquote(f_atom), unquote(args))
        |> Thunks.Freer.send(__MODULE__)
      end
    end
  end
end
