defmodule Freya.Effects.State do
  @moduledoc """
  A State effect implementation using the Freer monad.
  Combines Reader and Writer effects to provide stateful computations.
  """

  alias Freya.Freer
  alias Freya.Effects.Reader
  alias Freya.Effects.Writer

  @doc """
  Run a stateful computation with the given initial state.
  Returns a tuple with the result and final state.

  This implementation uses Reader and Writer effects to manage state.
  The Reader effect is used to get the current state,
  and the Writer effect is used to update the state.

  Implementation translated from:
  https://okmij.org/ftp/Haskell/extensible/more.pdf
  """
  def run(computation, initial_state) do
    Freer.handle_relay_s(
      computation,
      [Reader.Ops, Writer.Ops],
      initial_state,
      fn s -> fn x -> Freer.return({x, s}) end end,
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
  def run_expanded(computation, initial_state) do
    case computation do
      %Freer.Pure{val: x} ->
        Freer.return({x, initial_state})

      %Freer.Impure{eff: eff, mval: u, q: q} ->
        k = fn s -> Freer.q_comp(q, &run(&1, s)) end

        case {eff, u} do
          {Writer.Ops, {:put, o}} ->
            k.(o).(nil)

          {Reader.Ops, :get} ->
            k.(initial_state).(initial_state)

          _ ->
            %Freer.Impure{eff: eff, mval: u, q: [k.(initial_state)]}
        end
    end
  end
end
