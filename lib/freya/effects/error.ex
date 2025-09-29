defmodule Freya.Effects.Error.Constructors do
  @moduledoc "Constructors for the Error effect"

  @doc "Throw an error value"
  def throw_fx(error), do: {:throw, error}

  @doc "Catch errors in an inner computation with a handler"
  def catch_fx(computation, handler), do: {:catch, computation, handler}
end

defmodule Freya.Effects.Error do
  @moduledoc "Operations (Ops) for the Error effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Error.Constructors
end

defmodule Freya.Effects.ErrorHandler do
  @moduledoc "Interpreter (handler) for the Error effect"
  alias Freya.Freer

  @doc "Interpret an Error computation, handling throw/catch"
  def interpret_error(computation) do
    computation
    |> Freya.Freer.Impl.handle_relay(
      [Freya.Effects.Error],
      fn x -> Freya.RunOutcome.ensure(x) |> Freer.return() end,
      fn u, k ->
        case u do
          {:throw, err} ->
            Freya.RunOutcome.error(err) |> Freer.return()

          {:catch, inner, handler} ->
            inner
            |> interpret_error()
            |> Freer.bind(fn %Freya.RunOutcome{result: res} ->
              case Freya.Protocols.Result.type(res) do
                Freya.Freer.OkResult ->
                  k.(Freya.Protocols.Result.value(res))

                Freya.Freer.ErrorResult ->
                  err = Freya.Protocols.Result.value(res)

                  handler.(err)
                  |> interpret_error()
                  |> Freer.bind(fn %Freya.RunOutcome{result: res2} = rr ->
                    case Freya.Protocols.Result.type(res2) do
                      Freya.Freer.OkResult -> k.(Freya.Protocols.Result.value(res2))
                      _ -> Freer.return(rr)
                    end
                  end)
              end
            end)
        end
      end
    )
  end
end
