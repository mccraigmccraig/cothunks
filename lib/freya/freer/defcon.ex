defmodule Freya.Freer.Defcon do
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
