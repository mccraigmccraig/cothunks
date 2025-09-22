defmodule Freya.Defcon do
  @moduledoc """
  The `defcon` and `defconp` macros for defing effectful functions
  """

  @doc """
  Define a function whose body is a Freer.con block.

  Usage:
    defcon foo(a, b), [Reader, Writer] do
      c <- get()
      put(a + b)
      return(a + b + c)
    end

  With else:
    defcon foo(a), [Error] do
      _ <- Error.throw_fx(:bad)
      return(a)
    else
      :bad -> return(:ok)
    end
  """
  defmacro defcon(call_ast, mods_ast, do: body),
    do: Freya.Defcon.Impl.defcon(call_ast, mods_ast, body)

  defmacro defcon(call_ast, mods_ast, do: body, else: else_block),
    do: Freya.Defcon.Impl.defcon(call_ast, mods_ast, body, else_block)

  defmacro defconp(call_ast, mods_ast, do: body),
    do: Freya.Defcon.Impl.defconp(call_ast, mods_ast, body)

  defmacro defconp(call_ast, mods_ast, do: body, else: else_block),
    do: Freya.Defcon.Impl.defconp(call_ast, mods_ast, body, else_block)

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
