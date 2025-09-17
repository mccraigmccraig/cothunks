defmodule Freya.Effects.Coroutine do
  @moduledoc """
  A coroutine effect implementation using the Freer monad.
  Provides yield operation that suspends computation and returns a value to the caller.
  The computation can be resumed by providing a value that becomes the result of the yield operation.

  Based on the Haskell implementation in Control.Monad.Freer.Coroutine.
  """

  alias Freya.Freer
  alias Freya.FreerOps

  # Define the Yield effect
  defmodule Yield do
    defstruct [:value, :mapper]
  end

  # Define the Status type for coroutine state
  defmodule Status do
    defmodule Done do
      defstruct [:value]
    end

    defmodule Continue do
      defstruct [:value, :continuation]
    end
  end

  # Grammar for the coroutine effect
  defmodule Grammar do
    def yield(value, mapper), do: %Yield{value: value, mapper: mapper}
  end

  # Operations for the coroutine effect
  defmodule Ops do
    use FreerOps, ops: Grammar

    # 1-arity yield with identity mapper
    def yield(a) do
      yield(a, & &1)
    end
  end

  @doc """
  Reply to a coroutine effect by returning the Continue constructor.
  """
  def reply_c(%Yield{value: a, mapper: k}, arr) do
    Freer.return(%Status.Continue{
      value: a,
      continuation: fn b -> k.(b) |> arr.() end
    })
  end

  @doc """
  Run a coroutine and report its status.
  """
  def run(computation) do
    computation
    |> Freer.handle_relay(
      [Ops],
      fn x -> Freer.return(%Status.Done{value: x}) end,
      fn %Yield{} = y, k -> reply_c(y, k) end
    )
  end

  @doc """
  Resume a previously yielded coroutine with a value.
  """
  def resume(%Status.Continue{continuation: k}, input) do
    k.(input)
  end

  def resume(%Status.Done{value: value}, _input) do
    Freer.return(%Status.Done{value: value})
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
