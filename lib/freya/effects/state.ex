defmodule Freya.Effects.State do
  @moduledoc """
  A State effect implementation using the Freer monad.
  Combines Reader and Writer effects to provide stateful computations.
  """

  alias Freya.Freer
  alias Freya.Effects.Reader
  alias Freya.Effects.Writer

  @doc """
  Interpret a stateful computation with the given initial state.
  Returns a Freya.Result with :state in outputs.

  This implementation uses Reader and Writer effects to manage state.
  Implementation translated from:
  https://okmij.org/ftp/Haskell/extensible/more.pdf
  """
  def interpret_state(computation, initial_state) do
    Freer.handle_relay_s(
      computation,
      [Reader, Writer],
      initial_state,
      fn s ->
        fn x -> Freya.Result.ensure(x) |> Freya.Result.put(:state, s) |> Freer.return() end
      end,
      fn s ->
        fn u, k ->
          case u do
            {:put, o} -> k.(o).(nil)
            :get -> k.(s).(s)
          end
        end
      end
    )
  end

  # implemented without the help of the handle_relay_s helper
  # from the okmij papaer
  def interpret_state_expanded(computation, initial_state) do
    case computation do
      %Freer.Pure{val: x} ->
        Freer.return(Freya.Result.ensure(x) |> Freya.Result.put(:state, initial_state))

      %Freer.Impure{sig: eff, data: u, q: q} ->
        k = fn s -> Freer.q_comp(q, &interpret_state_expanded(&1, s)) end

        case {eff, u} do
          {Writer, {:put, o}} ->
            k.(o).(nil)

          {Reader, :get} ->
            k.(initial_state).(initial_state)

          _ ->
            %Freer.Impure{sig: eff, data: u, q: [k.(initial_state)]}
        end
    end
  end
end
