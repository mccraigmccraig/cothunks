defmodule Freya.Effects.Reader.Constructors do
  @moduledoc "Constructors for the Reader effect"

  @doc "Get the current environment value"
  def get(), do: :get
end

defmodule Freya.Effects.Reader do
  @moduledoc "Operations (Ops) for the Reader effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Reader.Constructors
end

defmodule Freya.Effects.ReaderHandler do
  @moduledoc "Interpreter (handler) for the Reader effect"
  alias Freya.Freer

  @doc "Interpret a reader computation with the given environment value"
  def interpret_reader(computation, reader_val) do
    computation
    |> Freya.Freer.Impl.handle_relay(
      [Freya.Effects.Reader],
      fn x -> Freya.Result.ensure(x) |> Freer.return() end,
      fn :get, k -> k.(reader_val) end
    )
  end
end
