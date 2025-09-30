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

defmodule Freya.Effects.Error.Handler do
  @moduledoc "Interpreter (handler) for the Error effect"

  require Logger

  alias Freya.ErrorResult
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Effects.Error
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
        %Freer.Impure{sig: _eff, data: u, q: q} = _computation,
        _handler_key,
        _state,
        %RunState{} = run_state
      ) do
    case u do
      {:throw, err} ->
        # Logger.error("#{__MODULE__}.throw")
        # throw shoft-circuits
        {Freya.ErrorResult.error(err) |> Freer.return(), nil}

      {:catch, inner, handler} ->
        {%Pure{val: result}, updated_run_state} = inner |> Run.interpret(run_state)

        case result do
          %ErrorResult{error: err} ->
            handler.(err)
            |> Run.interpret(updated_run_state)
            |> case do
              {%Pure{val: %ErrorResult{}}, _updated_run_state_2} ->
                # handling failed - rethrow original error
                {%Impure{sig: Error, data: {:throw, err}, q: q}, nil}

              {%Pure{val: val}, updated_run_state_2} ->
                # recovered - continue
                commit_k = fn val -> RunEffects.commit_states(val, updated_run_state_2.states) end
                updated_q = q |> Impl.q_prepend(commit_k)
                {Impl.q_apply(updated_q, val), nil}
            end

          res ->
            val = Result.value(res)
            # success - continue
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
