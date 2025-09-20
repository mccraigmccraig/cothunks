defmodule Freya.Effects.Error.Constructors do
  @moduledoc "Constructors for the Error effect"

  @doc "Throw an error value"
  def throw_fx(error), do: {:throw, error}

  @doc "Catch errors in an inner computation with a handler"
  def catch_fx(computation, handler), do: {:catch, computation, handler}


 end

defmodule Freya.Effects.Error do
  @moduledoc "Operations (Ops) for the Error effect"
  use Freya.FreerOps, constructors: Freya.Effects.Error.Constructors
end

defmodule Freya.Effects.ErrorHandler do
  @moduledoc "Interpreter (handler) for the Error effect"
  alias Freya.Freer

  @doc "Interpret an Error computation, handling throw/catch"
  def interpret_error(computation) do
    computation
    |> Freer.handle_relay(
      [Freya.Effects.Error],
      fn x -> Freya.Result.ensure(x) |> Freer.return end,
      fn u, k ->
        case u do
          {:throw, err} ->
            Freya.Result.new(nil, %{error: err}) |> Freer.return()

          {:catch, inner, handler} ->
            inner
            |> interpret_error()
            |> Freer.bind(fn %Freya.Result{} = r ->
              case Map.get(r.outputs, :error) do
                nil -> k.(Freya.Result.value(r))
                err ->
                  handler.(err)
                  |> interpret_error()
                  |> Freer.bind(fn %Freya.Result{} = rr -> k.(Freya.Result.value(rr)) end)
              end
            end)
        end
      end
    )
  end
end
