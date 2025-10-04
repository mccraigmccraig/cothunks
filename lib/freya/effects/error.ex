defmodule Freya.Effects.Error.Throw do
  defstruct error: nil
end

defmodule Freya.Effects.Error.Catch do
  defstruct computation: nil, handler: nil
end

defimpl Freya.Protocols.Sendable, for: Freya.Effects.Error.Throw do
  def send(%Freya.Effects.Error.Throw{} = eff),
    do: Freya.Freer.send_effect(eff, Freya.Effects.Error)
end

defimpl Freya.Protocols.Sendable, for: Freya.Effects.Error.Catch do
  def send(%Freya.Effects.Error.Catch{} = eff),
    do: Freya.Freer.send_effect(eff, Freya.Effects.Error)
end

defmodule Freya.Effects.Error do
  @moduledoc "Operations (Ops) for the Error effect"

  alias Freya.Effects.Error.Throw
  alias Freya.Effects.Error.Catch

  def throw_fx(err), do: %Throw{error: err}
  def catch_fx(computation, handler), do: %Catch{computation: computation, handler: handler}
end

defmodule Freya.Effects.Error.Handler do
  @moduledoc "Interpreter (handler) for the Error effect"

  require Logger

  alias Freya.ErrorResult
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Effects.Error
  alias Freya.Effects.Error.Throw
  alias Freya.Effects.Error.Catch
  alias Freya.Run
  alias Freya.Run.RunEffects
  alias Freya.Run.RunState
  alias Freya.ErrorResult
  alias Freya.Protocols.Result

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Error
  end

  @doc "Interpret an Error computation, handling throw/catch"
  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: Error, data: u, q: q} = _computation,
        _handler_key,
        _state,
        %RunState{} = run_state
      ) do
    case u do
      %Throw{error: err} ->
        # Logger.error("#{__MODULE__}.throw")
        # throw shoft-circuits - discards queue
        {Freya.ErrorResult.error(err) |> Freer.return(), nil}

      %Catch{computation: inner, handler: handler} ->
        {%Pure{val: result}, updated_run_state} = inner |> Run.interpret(run_state)

        case result do
          %ErrorResult{error: err} ->
            handler.(err)
            |> Run.interpret(updated_run_state)
            |> case do
              {%Pure{val: %ErrorResult{}}, _updated_run_state_2} ->
                # handling failed - rethrow original error, preserve queue
                # for handling later
                {%Impure{sig: Error, data: %Throw{error: err}, q: q}, nil}

              {%Pure{val: val}, updated_run_state_2} ->
                # recovered - continue and commit state updates
                commit_k = fn val -> RunEffects.commit_states(val, updated_run_state_2.states) end
                updated_q = q |> Impl.q_prepend(commit_k)
                {Impl.q_apply(updated_q, val), nil}
            end

          res ->
            val = Result.value(res)
            # success - continue and commit state updates
            commit_k = fn val -> RunEffects.commit_states(val, updated_run_state.states) end
            updated_q = q |> Impl.q_prepend(commit_k)
            {Impl.q_apply(updated_q, val), nil}
        end
    end
  end

  @impl Freya.EffectHandler
  def finalize(
        %Pure{} = computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    {computation, state}
  end
end
