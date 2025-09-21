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
    Freer.return(:nope)
  else
    :bad ->
      _ <- Writer.put({:handled, :bad})
      Freer.return(:ok)
  end

  """
  defmacro con(mod_or_mods, do: block) do
    imports = Con.expand_imports(mod_or_mods)

    quote do
      unquote_splicing(imports)
      unquote(Con.rewrite_block(block))
    end
  end

  defmacro con(mod_or_mods, do: block, else: else_block) do
    imports = Con.expand_imports(mod_or_mods)
    body = Con.rewrite_block(block)
    handler = Con.build_else_handler_fn(else_block)

    quote do
      unquote_splicing(imports)
      Freya.Effects.Error.catch_fx(unquote(body), unquote(handler))
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

  @spec send_effect(any, atom) :: freer
  def send_effect(fa, eff) do
    %Impure{sig: eff, data: fa, q: [&Freer.pure/1]}
  end

  # traditional name
  @spec etaf(any, atom) :: freer
  def etaf(fa, eff), do: send_effect(fa, eff)

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
