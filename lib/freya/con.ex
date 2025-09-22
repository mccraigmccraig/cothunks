defmodule Freya.Con do
  @moduledoc """
  The `con` macro for `with`-like effect binding syntax
  """

  defmacro con(mod_or_mods, do: do_block), do: Freya.Con.Impl.con(mod_or_mods, do_block)

  defmacro con(mod_or_mods, do: do_block, else: else_block),
    do: Freya.Con.Impl.con(mod_or_mods, do_block, else_block)

  defmodule Impl do
    def con(mod_or_mods, do_block) do
      imports = expand_imports(mod_or_mods)

      quote do
        unquote_splicing(imports)
        unquote(rewrite_block(do_block))
      end
    end

    def con(mod_or_mods, do_block, else_block) do
      imports = expand_imports(mod_or_mods)
      body = rewrite_block(do_block)
      handler = build_else_handler_fn(else_block)

      quote do
        unquote_splicing(imports)
        Freya.Effects.Error.catch_fx(unquote(body), unquote(handler))
      end
    end

    def expand_imports(mod_or_mods) do
      mods = mod_or_mods |> List.wrap()

      # always include the BaseOps in the imports
      all_mods = [Freya.Freer.BaseOps | mods] |> Enum.uniq()

      all_mods
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

      has_user_default =
        Enum.any?(clauses, fn
          {:->, _m, [[pattern], _rhs]} -> underscore_pattern?(pattern)
          _ -> false
        end)

      final_clauses =
        if has_user_default do
          built_clauses
        else
          default_err = Macro.var(:err, nil)

          default_clause =
            {:->, [],
             [[default_err], quote(do: Freya.Effects.Error.throw_fx(unquote(default_err)))]}

          built_clauses ++ [default_clause]
        end

      {:fn, [], final_clauses}
    end

    defp underscore_pattern?(ast) do
      case ast do
        {:_, _, _} -> true
        _ -> false
      end
    end
  end
end
