defmodule Thunks.Coroutine do
  @moduledoc """
  A coroutine effect implementation using the Freer monad.
  Provides yield operation that suspends computation and returns a value to the caller.
  The computation can be resumed by providing a value that becomes the result of the yield operation.
  """

  alias Thunks.Freer

  # Define structs for coroutine states
  defmodule Yielded do
    @moduledoc "Represents a suspended coroutine with a yielded value and continuation"
    defstruct [:value, :continuation]
  end

  defmodule Done do
    @moduledoc "Represents a completed coroutine with a final value"
    defstruct [:value]
  end

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
  Run a coroutine computation, handling the yield operations.
  Returns a Freer monad value that can be further processed by other effect handlers.

  When a yield operation is encountered, it creates an Impure value with the
  yielded value and continuation, allowing other effect handlers to process
  the computation before it's resumed.
  """
  def run(computation) do
    # Only accept Freer monad values (Pure or Impure)
    computation
    |> Freer.handle_relay(
      [Ops],
      &Freer.return/1,
      fn {:yield, value}, k ->
        # Create a special Freer value that represents a yielded computation
        # Using etaf is appropriate here because we're introducing a new effect
        # which captures a continuation for later processing by another handler
        Freer.etaf(%Yielded{value: value, continuation: k}, __MODULE__)
      end
    )
  end

  @doc """
  Extract the final result from a coroutine computation after all effects have been handled.
  Returns either:
  - %Done{value: value} for a completed computation
  - %Yielded{value: value, continuation: continuation} for a suspended computation
  """
  def extract(computation) do
    case computation do
      %Freer.Pure{val: value} ->
        %Done{value: value}

      %Freer.Impure{eff: __MODULE__, mval: %Yielded{value: value, continuation: k}, q: []} ->
        %Yielded{value: value, continuation: fn resume_value -> k.(resume_value) end}

      %Freer.Impure{eff: __MODULE__, mval: %Yielded{value: value, continuation: k}, q: q} ->
        # Handle the case where there are continuations after the yield
        %Yielded{
          value: value,
          continuation: fn resume_value ->
            # Make sure we return a proper Freer value that can be processed by run
            k.(resume_value) |> Freer.bindp(q)
          end
        }
    end
  end

  @doc """
  Resume a previously yielded coroutine with a value.
  Takes the result of extract/1 (a struct) and a resume value.
  Returns a new Freer value.
  """
  def resume(%Yielded{continuation: k}, resume_value) do
    # Just return the result from the continuation
    k.(resume_value)
  end

  def resume(%Done{value: value}, _resume_value) do
    Freer.return(value)
  end

  @doc """
  Run a coroutine to completion, collecting all yielded values and the final result.
  Takes an optional initial accumulator and a function to process each yield.
  """
  def run_collecting(computation, acc \\ [], yield_fn \\ fn v, a -> {v, [v | a]} end) do
    computation = run(computation)

    case extract(computation) do
      %Done{value: final_value} ->
        {final_value, Enum.reverse(acc)}

      %Yielded{value: yield_value, continuation: k} ->
        {resume_value, new_acc} = yield_fn.(yield_value, acc)
        # Resume and continue collecting
        resumed = resume(%Yielded{value: yield_value, continuation: k}, resume_value)
        run_collecting(resumed, new_acc, yield_fn)
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
          comp = run(comp)

          case extract(comp) do
            %Done{value: final_value} -> {[{:result, final_value}], :done}
            %Yielded{value: value, continuation: k} -> {[{:yielded, value}], {:suspended, k}}
          end

        {:suspended, k} ->
          # Pass a nil value to resume the coroutine
          next = resume(%Yielded{value: nil, continuation: k}, nil)
          next = run(next)

          case extract(next) do
            %Done{value: final_value} -> {[{:result, final_value}], :done}
            %Yielded{value: value, continuation: new_k} -> {[{:yielded, value}], {:suspended, new_k}}
          end

        :done ->
          {:halt, nil}
      end,
      fn _ -> nil end
    )
  end
end
