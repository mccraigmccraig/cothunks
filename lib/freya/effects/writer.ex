defmodule Freya.Effects.Writer do
  @moduledoc """
  A Writer effect implementation using the Freer monad.
  Provides a way to accumulate output.
  """

  alias Freya.Freer

  # Grammar for the writer effect
  defmodule Grammar do
    @doc """
    Output a value to the writer's log
    """
    def put(o), do: {:put, o}
  end

  # Operations for the writer effect
  defmodule Ops do
    use Freya.FreerOps, ops: Freya.Effects.Writer.Grammar
  end

  @doc """
  Run a writer computation, returning a tuple with the result and accumulated output
  """
  def run(computation) do
    computation
    |> Freer.handle_relay(
      [Ops],
      fn x -> Freya.Result.ensure(x) |> Freer.return end,
      fn {:put, o}, k ->
        k.(nil)
        |> Freer.bind(fn %Freya.Result{} = r ->
          list = Map.get(r.outputs, :writer, [])
          r |> Freya.Result.put(:writer, [o | list]) |> Freer.return
        end)
      end
    )
  end
end
