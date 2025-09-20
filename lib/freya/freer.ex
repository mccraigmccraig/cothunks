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

  @doc """
  con - profitable cheating -and Spanish/Italian `with`

  macro sugar which rewrites a with-like statement into
  Frrer.bind steps

  con [Reader, Writer] do
    a <- get()
    put(a + 5)
    return(a + 10)
  end
  """
  defmacro con(mod_or_mods, do: block) do
    imports = expand_imports(mod_or_mods)

    quote do
      unquote_splicing(imports)
      unquote(rewrite_block(block))
    end
  end

  defmacro con(mod_or_mods, do: block, else: else_block) do
    imports = expand_imports(mod_or_mods)
    body = rewrite_block(block)
    handler = build_else_handler_fn(else_block)

    quote do
      unquote_splicing(imports)
      Freya.Effects.Error.catch_fx(unquote(body), unquote(handler))
    end
  end

  defp expand_imports(mod_or_mods) do
    mod_or_mods
    |> List.wrap()
    |> Enum.map(fn mod ->
      quote do
        import unquote(mod)
      end
    end)
  end

  defp rewrite_block({:__block__, _, exprs}), do: rewrite_exprs(exprs)
  defp rewrite_block(expr), do: rewrite_exprs([expr])

  defp rewrite_exprs([last]) do
    last
  end

  defp rewrite_exprs([{:<-, _m, [lhs, rhs]} | rest]) do
    binder(lhs, rhs, rewrite_exprs(rest))
  end

  defp rewrite_exprs([expr | rest]) do
    binder(quote(do: _), expr, rewrite_exprs(rest))
  end

  defp binder(lhs, rhs, body) do
    quote do
      unquote(rhs)
      |> Freer.bind(fn unquote(lhs) -> unquote(body) end)
    end
  end

  # Build a multi-clause fn from an else block with `->` clauses
  defp build_else_handler_fn(else_block) do
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

  # aka etaf
  @spec send_effect(any, atom) :: freer
  def send_effect(fa, eff) do
    %Impure{sig: eff, data: fa, q: [&Freer.pure/1]}
  end

  @spec return(any) :: freer
  def return(x), do: pure(x)

  @spec bind(freer, (any -> freer)) :: freer
  def bind(%Pure{val: x}, k), do: k.(x)

  def bind(%Impure{sig: sig, data: u, q: q}, k),
    do: %Impure{sig: sig, data: u, q: Freya.Freer.Impl.q_append(q, k)}

  @doc """
  after all effects are handled, only %Pure{} is left
  """
  @spec run(freer) :: any
  def run(%Pure{val: x}), do: x

  def run(%Impure{sig: sig, data: _u, q: _q} = impure) do
    raise "unhandled effect: #{sig} - #{inspect(impure)}"
  end
end
