defmodule Freya.Freer.Con do
  @moduledoc """
  Supporting functions for the Freya.Freer.con macro
  """

  def expand_imports(mod_or_mods) do
    mod_or_mods
    |> List.wrap()
    |> Enum.map(fn mod ->
      quote do
        import unquote(mod)
      end
    end)
  end

  def rewrite_block({:__block__, _, exprs}), do: rewrite_exprs(exprs)
  def rewrite_block(expr), do: rewrite_exprs([expr])

  def rewrite_exprs([last]) do
    last
  end

  def rewrite_exprs([{:<-, _m, [lhs, rhs]} | rest]) do
    binder(lhs, rhs, rewrite_exprs(rest))
  end

  def rewrite_exprs([expr | rest]) do
    binder(quote(do: _), expr, rewrite_exprs(rest))
  end

  def binder(lhs, rhs, body) do
    quote do
      unquote(rhs)
      |> Freya.Freer.bind(fn unquote(lhs) -> unquote(body) end)
    end
  end

  # Build a multi-clause fn from an else block with `->` clauses
  def build_else_handler_fn(else_block) do
    clauses =
      case else_block do
        {:__block__, _, exprs} -> exprs
        single_list when is_list(single_list) -> single_list
        single -> [single]
      end

    built_clauses =
      Enum.map(clauses, fn
        {:->, meta, [[pattern], rhs]} ->
          body_ast =
            case rhs do
              {:__block__, _, exprs} -> rewrite_block({:__block__, [], exprs})
              list when is_list(list) -> rewrite_block({:__block__, [], list})
              other -> rewrite_block(other)
            end

          {:->, meta, [[pattern], body_ast]}

        other ->
          raise ArgumentError,
                "Freer.con else expects `pattern -> expr` clauses, got: #{inspect(other, pretty: true)}"
      end)

    default_err = Macro.var(:err, nil)

    default_clause =
      {:->, [], [[default_err], quote(do: Freya.Effects.Error.throw_fx(unquote(default_err)))]}

    {:fn, [], built_clauses ++ [default_clause]}
  end
end
