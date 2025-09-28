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

  # Freer values are %Pure{} and %Impure{}

  defmodule Pure do
    defstruct val: nil

    @type t :: %__MODULE__{
            val: any
          }
  end

  defmodule Impure do
    defstruct sig: nil, data: nil, q: []

    @type t :: %__MODULE__{
            sig: atom,
            data: any,
            # should be list((any->freer))
            q: list((any -> any))
          }
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

  @doc """
  Run a computation after binding a Finalize on the normal Ok path.

  This ensures a Finalize effect is emitted at the outer boundary for
  normal completion, allowing EffectLogger (or a FinalizeNoop handler)
  to observe and consume it.
  """
  @spec run_with_finalize(freer) :: any
  def run_with_finalize(comp) do
    comp
    |> bind(fn x -> Freya.Effects.Finalize.finalize(Freya.RunOutcome.ensure(x)) end)
    |> run()
  end
end
