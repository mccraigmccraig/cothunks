defmodule Freya.Freer.Defcon do
  @moduledoc """
  supporting functions for the `Freya.Freer.defcon`
  and `Freya.Freer.defconp` macros
  """

  defmacro defcon(call_ast, mods_ast, do: body),
    do: Freya.Freer.Defcon.Impl.defcon(call_ast, mods_ast, body)

  defmacro defcon(call_ast, mods_ast, do: body, else: else_block),
    do: Freya.Freer.Defcon.Impl.defcon(call_ast, mods_ast, body, else_block)

  defmacro defconp(call_ast, mods_ast, do: body),
    do: Freya.Freer.Defcon.Impl.defconp(call_ast, mods_ast, body)

  defmacro defconp(call_ast, mods_ast, do: body, else: else_block),
    do: Freya.Freer.Defcon.Impl.defconp(call_ast, mods_ast, body, else_block)

  defmodule Impl do
    def defcon(call_ast, mods_ast, body) do
      mods_list = List.wrap(mods_ast)

      quote do
        def unquote(call_ast) do
          Freya.Freer.con unquote(mods_list) do
            unquote(body)
          end
        end
      end
    end

    def defcon(call_ast, mods_ast, body, else_block) do
      mods_list = List.wrap(mods_ast)

      quote do
        def unquote(call_ast) do
          Freya.Freer.con(unquote(mods_list), do: unquote(body), else: unquote(else_block))
        end
      end
    end

    @doc """
    Private variant of defcon. Defines a defp with a Freer.con body.
    """
    def defconp(call_ast, mods_ast, body) do
      mods_list = List.wrap(mods_ast)

      quote do
        defp unquote(call_ast) do
          Freya.Freer.con unquote(mods_list) do
            unquote(body)
          end
        end
      end
    end

    def defconp(call_ast, mods_ast, body, else_block) do
      mods_list = List.wrap(mods_ast)

      quote do
        defp unquote(call_ast) do
          Freya.Freer.con(unquote(mods_list), do: unquote(body), else: unquote(else_block))
        end
      end
    end
  end
end
