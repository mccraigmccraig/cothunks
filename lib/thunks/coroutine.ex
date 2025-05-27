defmodule Thunks.Coroutine do
  @moduledoc """
  A coroutine effect implementation using the Freer monad.
  Provides yield operation that suspends computation and returns a value to the caller.
  The computation can be resumed by providing a value that becomes the result of the yield operation.
  """

  alias Thunks.Freer

  # Grammar for the coroutine effect
  defmodule Grammar do
    @doc """
    Yield a value to the calling context and suspend computation
    until resumed with a new value.
    """
    def yield(value), do: {:yield, value}
  end

  # Operations for the coroutine effect
  defmodule Ops do
    use Thunks.FreerOps, ops: Thunks.Coroutine.Grammar
  end

  @doc """
  Run a coroutine computation, returning a tuple with:
  - :done and the final value if the computation completes
  - :yielded, the yielded value, and a continuation function that takes a resume value
  """
  def run(computation) do
    computation
    |> Freer.handle_relay(
      [Ops],
      fn value -> {:done, value} end,
      fn {:yield, value}, k ->
        {:yielded, value, fn resume_value -> k.(resume_value) end}
      end
    )
  end

  @doc """
  Run a coroutine to completion, collecting all yielded values and the final result.
  Takes an optional initial accumulator and a function to process each yield.
  """
  def run_collecting(computation, acc \\ [], yield_fn \\ fn v, a -> {v, [v | a]} end) do
    case run(computation) do
      {:done, final_value} ->
        {final_value, Enum.reverse(acc)}

      {:yielded, yield_value, k} ->
        {resume_value, new_acc} = yield_fn.(yield_value, acc)
        run_collecting(k.(resume_value), new_acc, yield_fn)
    end
  end

  @doc """
  Run a coroutine step by step, yielding control back to the caller after each yield.
  Returns a stream that will produce each yielded value and finally the result.
  """
  def run_stream(computation) do
    Stream.resource(
      fn -> {:start, computation} end,
      fn
        {:start, comp} ->
          case run(comp) do
            {:done, final_value} -> {[{:result, final_value}], :done}
            {:yielded, value, k} -> {[{:yielded, value}], {:suspended, k}}
          end

        {:suspended, k} ->
          case run(k.(nil)) do
            {:done, final_value} -> {[{:result, final_value}], :done}
            {:yielded, value, new_k} -> {[{:yielded, value}], {:suspended, new_k}}
          end

        :done ->
          {:halt, nil}
      end,
      fn _ -> nil end
    )
  end
end
