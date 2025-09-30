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
        %RunState{} = run_state
      ) do
    case u do
      # shoft-circuit - discard queue - it lives on in k
      %Yield{value: val} ->
        k = fn v -> Impl.q_apply(q, v) end
        {YieldResult.yield(val, k, run_state.states) |> Freer.return(), nil}
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
          result: %Freya.YieldResult{continuation: k, states: states}
        },
        input,
        %RunState{} = run_state
      ) do
    run_state = %{run_state | states: states}
    Run.run(k.(input), run_state)
  end

  # @doc """
  # Run a coroutine to completion, collecting all yielded values and the final result.
  # Takes an optional initial accumulator and a function to process each yield.
  # """
  # def run_collecting(computation, acc \\ [], yield_fn \\ fn v, a -> {v, [v | a]} end) do
  #   result = run(computation)

  #   case Freer.run(result) do
  #     %Status.Done{value: final_value} ->
  #       {final_value, Enum.reverse(acc)}

  #     %Status.Continue{value: yield_value, continuation: k} ->
  #       {resume_value, new_acc} = yield_fn.(yield_value, acc)
  #       # Resume and continue collecting
  #       resumed = resume(%Status.Continue{value: yield_value, continuation: k}, resume_value)
  #       run_collecting(resumed, new_acc, yield_fn)
  #   end
  # end

  # @doc """
  # Run a coroutine step by step, yielding control back to the caller after each yield.
  # Returns a stream that will produce each yielded value and finally the result.
  # """
  # def run_stream(computation) do
  #   Stream.resource(
  #     fn -> {:start, computation} end,
  #     fn
  #       {:start, comp} ->
  #         result = run(comp)
  #         status = Freer.run(result)

  #         case status do
  #           %Status.Done{value: final_value} ->
  #             {[{:result, final_value}], :done}

  #           %Status.Continue{value: value, continuation: k} ->
  #             {[{:yielded, value}], {:suspended, k}}
  #         end

  #       {:suspended, k} ->
  #         # Pass a nil value to resume the coroutine
  #         next = resume(%Status.Continue{value: nil, continuation: k}, nil)
  #         status = Freer.run(run(next))

  #         case status do
  #           %Status.Done{value: final_value} ->
  #             {[{:result, final_value}], :done}

  #           %Status.Continue{value: value, continuation: new_k} ->
  #             {[{:yielded, value}], {:suspended, new_k}}
  #         end

  #       :done ->
  #         {:halt, nil}
  #     end,
  #     fn _ -> nil end
  #   )
  # end
end
