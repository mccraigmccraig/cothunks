defmodule Freya.Effects.Error do
  @moduledoc "Operations (Ops) for the Error effect"
  import Freya.Sig.DefEffectStruct

  def_effect_struct(Throw, error: nil)
  def_effect_struct(Catch, computation: nil, handler: nil)

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
  alias Freya.Effects.Error
  alias Freya.Effects.Error.Throw
  alias Freya.Effects.Error.Catch
  alias Freya.Run
  alias Freya.Run.RunEffects
  alias Freya.Run.RunEffects.ScopedResult
  alias Freya.Run.RunState
  alias Freya.RunOutcome
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
        # {%Pure{val: result}, updated_run_state}
        %RunOutcome{
          result: result
        } = inner_outcome = Run.run(inner, run_state)

        case result do
          %ErrorResult{error: err} ->
            handler.(err)
            |> Run.run(inner_outcome.run_state)
            |> case do
              %RunOutcome{result: %ErrorResult{}} = unrecovered_outcome ->
                discard_k = fn val -> RunEffects.scoped_result(val, unrecovered_outcome) end
                updated_q = q |> Impl.q_prepend(discard_k)
                # handling failed - rethrow original error, preserve queue
                # for handling later
                {%Impure{sig: Error, data: %Throw{error: err}, q: updated_q}, nil}

              %RunOutcome{result: result} = recovered_outcome ->
                val = Result.value(result)

                # recovered - continue and commit state updates

                # commit_k = fn val -> RunEffects.scoped_ok(val, recovered_outcome) end
                # updated_q = q |> Impl.q_prepend(commit_k)

                # Logger.error(
                #   "#{__MODULE__}.recovered updated_q: #{inspect(updated_q, pretty: true)}"
                # )

                {%Impure{
                   sig: RunEffects,
                   data: %ScopedResult{
                     computation: Freer.return(val),
                     run_outcome: recovered_outcome
                   },
                   q: q
                 }, nil}
            end

          res ->
            val = Result.value(res)

            # commit_k = fn val -> RunEffects.scoped_ok(val, inner_outcome) end
            # updated_q = q |> Impl.q_prepend(commit_k)
            {%Impure{
               sig: RunEffects,
               data: %ScopedResult{
                 computation: Freer.return(val),
                 run_outcome: inner_outcome
               },
               q: q
             }, nil}
        end
    end
  end
end
