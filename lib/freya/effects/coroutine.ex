# Define the Yield effect
defmodule Freya.Effects.Coroutine.Yield do
  defstruct [:value]
end

# Define the Status type for coroutine state
# Status structs are superseded by RunOutcome with OkResult/YieldResult

# Constructors for the coroutine effect
defmodule Freya.Effects.Coroutine.Constructors do
  alias Freya.Effects.Coroutine.Yield

  def yield(value), do: %Yield{value: value}
end

# Operations for the coroutine effect
defmodule Freya.Effects.Coroutine do
  use Freya.Freer.Ops, constructors: Freya.Effects.Coroutine.Constructors
end

defmodule Freya.Effects.Coroutine.Handler do
  @moduledoc """
  A coroutine effect implementation using the Freer monad.
  Provides yield operation that suspends computation and returns a value to the caller.
  The computation can be resumed by providing a value that becomes the result of the yield operation.

  Based on the Haskell implementation in Control.Monad.Freer.Coroutine.
  """

  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Effects.Coroutine
  alias Freya.Effects.Coroutine.Yield
  alias Freya.RunOutcome
  alias Freya.Run.RunState
  alias Freya.Run
  alias Freya.YieldResult

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Coroutine
  end

  @doc """
  Interpret a coroutine and report its status.
  """
  @impl Freya.EffectHandler
  def interpret(
        %Impure{sig: Coroutine, data: u, q: q} = _computation,
        _handler_key,
        _state,
        %RunState{}
      ) do
    case u do
      # shoft-circuit - discard queue - it lives on in k
      %Yield{value: val} ->
        k = fn v -> Impl.q_apply(q, v) end
        {YieldResult.yield(val, k) |> Freer.return(), nil}
    end
  end

  @impl Freya.EffectHandler
  def finalize(
        %Pure{} = computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    {computation, state}
  end

  @doc """
  Resume a previously yielded coroutine with a value.
  """
  def resume(
        %RunOutcome{
          result: %Freya.YieldResult{continuation: k},
          run_state: run_state
        },
        input
      ) do
    Run.run(k.(input), run_state)
  end
end
