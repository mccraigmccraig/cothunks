defmodule Thunks.Writer do
  @moduledoc """
  A Writer effect implementation using the Freer monad.
  Provides a way to accumulate output.
  """

  alias Thunks.Freer

  # Grammar for the writer effect
  defmodule Grammar do
    @doc """
    Output a value to the writer's log
    """
    def put(o), do: {:put, o}
  end

  # Operations for the writer effect
  defmodule Ops do
    use Thunks.FreerOps, ops: Thunks.Writer.Grammar
  end

  @doc """
  Run a writer computation, returning a tuple with the result and accumulated output
  """
  def run(computation) do
    computation
    |> Freer.handle_relay(
      [Ops],
      fn x -> Freer.return({x, []}) end,
      fn {:put, o}, k -> k.(nil) |> Freer.bind(fn {x, l} -> Freer.return({x, [o | l]}) end) end
    )
  end
end
