defmodule Freya.Freer do
  @moduledoc """
  A Freer Monad with extensible effects, based on the paper:
  https://okmij.org/ftp/Haskell/extensible/more.pdf

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  https://github.com/bootstarted/effects
  """
  require Logger

  alias Freya.Freer
  alias Freya.Freer.Con

  @doc """
  con - profitable cheating -and Spanish/Italian `with`

  macro sugar which rewrites a with-like statement into
  Freer.bind steps - similar to Haskell `do` notation

  con [Reader, Writer] do
    a <- get()
    put(a + 5)
    return(a + 10)
  end

  there's also an `else` clause which translates into an Error
  effect catch_fx operation

  Freer.con [Error, Writer] do
    _ <- put(:before)
    _ <- throw_fx(:bad)
    _ <- put(:after)
    return(:nope)
  else
    :bad ->
      _ <- put({:handled, :bad})
      return(:ok)
  end

  """
  defmacro con(mod_or_mods, do: do_block), do: Con.con(mod_or_mods, do_block)

  defmacro con(mod_or_mods, do: do_block, else: else_block),
    do: Con.con(mod_or_mods, do_block, else_block)

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
  defmacro defcon(call_ast, mods_ast, do: body) do
    mods_list = List.wrap(mods_ast)

    quote do
      def unquote(call_ast) do
        Freya.Freer.con unquote(mods_list) do
          unquote(body)
        end
      end
    end
  end

  defmacro defcon(call_ast, mods_ast, do: body, else: else_block) do
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
  defmacro defconp(call_ast, mods_ast, do: body) do
    mods_list = List.wrap(mods_ast)

    quote do
      defp unquote(call_ast) do
        Freya.Freer.con unquote(mods_list) do
          unquote(body)
        end
      end
    end
  end

  defmacro defconp(call_ast, mods_ast, do: body, else: else_block) do
    mods_list = List.wrap(mods_ast)

    quote do
      defp unquote(call_ast) do
        Freya.Freer.con(unquote(mods_list), do: unquote(body), else: unquote(else_block))
      end
    end
  end

  # Freer values are %Pure{} and %Impure{}

  defmodule Pure do
    defstruct val: nil
  end

  defmodule Impure do
    defstruct sig: nil, data: nil, q: []
  end

  @type freer() :: %Pure{} | %Impure{}

  def freer?(%Pure{}), do: true
  def freer?(%Impure{}), do: true
  def freer?(_), do: false

  # now the Freer functions

  @spec pure(any) :: freer
  def pure(x), do: %Pure{val: x}

  @doc """
  send an effect data-structure for interpretation

  `sig` identifies the operations module definint the effect signature -
  (the set of operation functions available for the effect)
  """
  @spec send_effect(any, atom) :: freer
  def send_effect(fa, sig) do
    %Impure{sig: sig, data: fa, q: [&Freer.pure/1]}
  end

  @doc """
  the same as `send_effect` - `etaf` is the name of the function in the
  `more.pdf` paper
  """
  @spec etaf(any, atom) :: freer
  def etaf(fa, sig), do: send_effect(fa, sig)

  @spec return(any) :: freer
  def return(x), do: pure(x)

  @spec bind(freer, (any -> freer)) :: freer
  def bind(%Pure{val: x}, k), do: k.(x)

  def bind(%Impure{sig: sig, data: u, q: q}, k),
    do: %Impure{sig: sig, data: u, q: Freya.Freer.Impl.q_append(q, k)}

  @doc """
  After all effects are handled, only %Pure{} is left. Extracts the
  final value

  make sure you handle all effects eith Effect.interpret_*
  calls before extracting the final value - or there will be
  a runtime error
  """
  @spec run(freer) :: any
  def run(%Pure{val: x}), do: x

  def run(%Impure{sig: sig, data: _u, q: _q} = impure) do
    raise "unhandled effect: #{sig} - #{inspect(impure)}"
  end
end
