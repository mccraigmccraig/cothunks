defmodule Freya.Effects.Reader do
  @moduledoc """
  A Reader effect implementation using the Freer monad.
  Provides a way to read from an environment.
  """

  alias Freya.Freer

  # Grammar for the reader effect
  defmodule Grammar do
    @doc """
    Get the current environment value
    """
    def get(), do: :get
  end

  # Operations for the reader effect
  defmodule Ops do
    use Freya.FreerOps, ops: Freya.Effects.Reader.Grammar
  end

  @doc """
  Run a reader computation with the given environment value
  """
  def run(computation, reader_val) do
    computation
    |> Freer.handle_relay(
      [Ops],
      fn x -> Freya.Result.ensure(x) |> Freer.return end,
      fn :get, k -> k.(reader_val) end
    )
  end
end
