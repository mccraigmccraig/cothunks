defmodule Freya.Effects.State do
  @moduledoc """
  A State effect implementation using the Freer monad.
  Combines Reader and Writer effects to provide stateful computations.
  """

  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Effects.Reader
  alias Freya.Effects.Writer

  defmodule StateExpanded do
    @behaviour Freya.EffectHandler

    @impl true
    def handles?(%Impure{sig: sig, data: _data, q: _q}) do
      sig in [Reader, Writer]
    end

    @impl true
    def interpret(computation, _handler_key, state, _all_states) do
      case computation do
        %Freer.Pure{val: _x} = pure ->
          {pure, state}

        %Freer.Impure{sig: eff, data: u, q: q} ->
          case {eff, u} do
            {Writer, {:put, o}} ->
              {Impl.q_apply(q, nil), o}

            {Reader, :get} ->
              {Impl.q_apply(q, state), state}

            _ ->
              {%Freer.Impure{sig: eff, data: u, q: q}, state}
          end
      end
    end
  end

  @doc """
  Interpret a stateful computation with the given initial state.
  Returns a Freya.RunOutcome with :state in outputs.

  This implementation uses Reader and Writer effects to manage state.
  Implementation translated from:
  https://okmij.org/ftp/Haskell/extensible/more.pdf
  """
  def interpret_state(computation, initial_state) do
    Freya.Freer.Impl.handle_relay_s(
      computation,
      [Reader, Writer],
      initial_state,
      fn s ->
        fn x ->
          Freya.RunOutcome.ensure(x) |> Freya.RunOutcome.put(:state, s) |> Freer.return()
        end
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
        Freer.return(Freya.RunOutcome.ok(x) |> Freya.RunOutcome.put(:state, initial_state))

      %Freer.Impure{sig: eff, data: u, q: q} ->
        k = fn s -> Freya.Freer.Impl.q_comp(q, &interpret_state_expanded(&1, s)) end

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
