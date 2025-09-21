defmodule Freya.Effects.Writer.Constructors do
  @moduledoc "Constructors for the Writer effect"

  @doc "Output a value to the writer's log"
  def put(o), do: {:put, o}
end

defmodule Freya.Effects.Writer do
  @moduledoc "Operations (Ops) for the Writer effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Writer.Constructors
end

defmodule Freya.Effects.WriterHandler do
  @moduledoc "Interpreter (handler) for the Writer effect"
  alias Freya.Freer

  @doc "Interpret a writer computation, accumulating output in Freya.Result.outputs[:writer]"
  def interpret_writer(computation) do
    computation
    |> Freya.Freer.Impl.handle_relay(
      [Freya.Effects.Writer],
      fn x -> Freya.Result.ensure(x) |> Freer.return() end,
      fn {:put, o}, k ->
        k.(nil)
        |> Freer.bind(fn %Freya.Result{} = r ->
          list = Map.get(r.outputs, :writer, [])
          r |> Freya.Result.put(:writer, [o | list]) |> Freer.return()
        end)
      end
    )
  end
end
