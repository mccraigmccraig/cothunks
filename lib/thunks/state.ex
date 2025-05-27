defmodule Thunks.State do
  @moduledoc """
  A State effect implementation using the Freer monad.
  Combines Reader and Writer effects to provide stateful computations.
  """

  alias Thunks.Freer
  alias Thunks.Reader
  alias Thunks.Writer

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
            %Freer.Impure{eff: eff, mval: u, q: [k]}
        end
    end
  end
end
