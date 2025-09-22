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

defmodule Freya.Effects.CoroutineHandler do
  @moduledoc """
  A coroutine effect implementation using the Freer monad.
  Provides yield operation that suspends computation and returns a value to the caller.
  The computation can be resumed by providing a value that becomes the result of the yield operation.

  Based on the Haskell implementation in Control.Monad.Freer.Coroutine.
  """

  alias Freya.Freer
  alias Freya.Effects.Coroutine.Yield
  alias Freya.RunOutcome

  @doc """
  Reply to a coroutine effect by returning the Continue constructor.
  """
  def reply_c(%Yield{value: a}, k) do
    Freer.return(RunOutcome.yield(a, fn b -> k.(b) end))
  end

  @doc """
  Interpret a coroutine and report its status.
  """
  def interpret_coroutine(computation) do
    computation
    |> Freya.Freer.Impl.handle_relay(
      [Freya.Effects.Coroutine],
      fn x -> Freer.return(RunOutcome.ensure(x)) end,
      fn %Yield{} = y, k -> reply_c(y, k) end
    )
  end

  @doc """
  Resume a previously yielded coroutine with a value.
  """
  def resume(%RunOutcome{result: %Freya.Freer.YieldResult{continuation: k}}, input), do: k.(input)
  def resume(%RunOutcome{} = out, _input), do: Freer.return(out)

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
