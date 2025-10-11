defmodule Freya.Run do
  @moduledoc """
  Functions to manage a priority-list of EffectHandlers and run a computation
  in the context of that list of EffectHandlers

  EffectHandlers are structs implementing the EffectHandler behaviour
  """
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.OkResult
  alias Freya.Freer.Pure
  alias Freya.Protocols.Result
  alias Freya.Protocols.Sendable
  alias Freya.Run.RunEffects
  alias Freya.Run.RunEffects.ScopedResult
  alias Freya.Run.RunState
  alias Freya.RunOutcome

  require Logger

  @type handler_mod_with_state :: {RunState.handler_key(), any}
  @type handler_spec :: RunState.handler_mod() | handler_mod_with_state()
  @type handler_spec_list :: list({RunState.handler_key(), handler_spec})

  @doc """
  Build a RunState struct with the provided EffectHandlers, and their initial state
  """
  @spec with_handlers(handler_spec_list()) :: %RunState{}
  def with_handlers(handler_specs) do
    # silently add the RunEffects handler
    handler_specs = handler_specs ++ [run: RunEffects.Handler]

    handler_specs
    |> Enum.map(fn
      {key, mod} when is_atom(key) and is_atom(mod) -> {key, {mod, nil}}
      {key, {mod, _state}} = spec_with_state when is_atom(key) and is_atom(mod) -> spec_with_state
    end)
    |> Enum.reduce(
      %RunState{handlers: [], states: %{}},
      fn {key, {mod, state}}, acc ->
        if Map.has_key?(acc, key) do
          raise ArgumentError,
            message:
              "#{__MODULE__}.register_handler haneler_key already exists\n" <>
                "handler_key: #{inspect(key)}\n" <>
                "%run{}: #{inspect(acc, pretty: true)}"
        end

        # make sure the EffectHandler behaviours are loaded!
        Code.ensure_loaded(mod)

        %{
          acc
          | handlers: [{key, mod} | acc.handlers],
            states: Map.put(acc.states, key, state)
        }
      end
    )
    |> then(fn %RunState{handlers: handlers} = self ->
      %{self | handlers: Enum.reverse(handlers)}
    end)
  end

  @doc """
  Resume a suspended computation with a value.
  """
  def resume(
        %RunOutcome{
          result: %Freya.SuspendResult{continuation: k},
          run_state: run_state
        },
        input
      ) do
    run(k.(input), run_state)
  end

  @doc """
  Interpret effects and finalize outputs - the main client-facing
  computation runner
  """
  @spec run(Freer.freer(), RunState.t()) :: RunOutcome.t()
  def run(
        %Pure{} = computation,
        %RunState{} = run_state
      ) do
    # should all effects get a shot at the result ? maybe not
    {%Pure{val: final_val}, final_run_state} = finalize(computation, run_state)

    %RunOutcome{
      result: final_val,
      outputs: final_run_state.states,
      run_state: run_state
    }
  end

  def run(
        %Impure{} = computation,
        %RunState{} = run_state
      ) do
    updated_run_state = initialize(computation, run_state)

    {new_computation, updated_run_state} = interpret(computation, updated_run_state)

    # Logger.error("#{__MODULE__}.after-interpret")
    # it's %Pure{} now
    run(new_computation, updated_run_state)
  end

  def run(
        sendable,
        %RunState{} = run_state
      ) do
    computation = Sendable.send(sendable)

    if computation == sendable do
      raise ArgumentError,
        message:
          "#{__MODULE__}.run - not Sendable: #{inspect(sendable, pretty: true)} - " <>
            " do you need to return() ?"
    end

    run(computation, run_state)
  end

  # initialize output value and states - gives each Effect chance to initialize
  # its state and the result value
  @spec initialize(Freer.freer(), RunState.t()) :: RunState.t()
  defp initialize(
         computation,
         %RunState{
           handlers: handlers
         } = run_state
       ) do
    handlers
    |> Enum.reduce(run_state, fn {key, mod}, run_state ->
      if function_exported?(mod, :initialize, 4) do
        updated_state =
          mod.initialize(computation, key, Map.get(run_state.states, key), run_state)

        %{run_state | states: Map.put(run_state.states, key, updated_state)}
      else
        run_state
      end
    end)
  end

  # finalize output value and states - gives each Effect chance to finalize
  # its state and the result value
  @spec finalize(Pure.t(), RunState.t()) :: {Pure.t(), RunState.t()}
  defp finalize(
         %Pure{val: val} = computation,
         %RunState{
           handlers: handlers
         } = run_state
       ) do
    # if we get to the finalize phase and no effect has decided upon
    # what type of output it's going to be, then it's an OkResult,
    # signalling a normal completion
    computation = if !Result.type(val), do: %Pure{val: %OkResult{value: val}}, else: computation

    handlers
    |> Enum.reduce({computation, run_state}, fn {key, mod}, {pure, run_state} ->
      if function_exported?(mod, :finalize, 4) do
        # Logger.error("#{inspect(pure)}\n#{inspect(key)}\n#{inspect(run_state)}")
        {pure, updated_state} = mod.finalize(pure, key, Map.get(run_state.states, key), run_state)
        {pure, %{run_state | states: Map.put(run_state.states, key, updated_state)}}
      else
        {computation, run_state}
      end
    end)
  end

  # use the EffectHandler.scoped_return function to update each of the
  # effect states after a scoped handler returns
  #
  # returns: an updated Map of effect states
  @spec scoped_return(RunState.t(), ScopedResult.t()) :: map
  defp scoped_return(
         %RunState{handlers: handlers, states: effect_states} = run_state,
         %ScopedResult{
           computation: computation,
           run_outcome: %RunOutcome{
             result: scoped_effect_result,
             run_state: %RunState{states: scoped_effect_states}
           }
         }
       ) do
    handlers
    |> Enum.reduce(effect_states, fn {key, mod}, effect_states ->
      if function_exported?(mod, :scoped_return, 6) do
        updated_effect_state =
          mod.scoped_return(
            scoped_effect_result,
            computation,
            key,
            Map.get(effect_states, key),
            Map.get(scoped_effect_states, key),
            run_state
          )

        Map.put(effect_states, key, updated_effect_state)
      else
        case scoped_effect_result do
          %Freya.OkResult{} ->
            # accept the scoped state
            Map.put(effect_states, key, Map.get(scoped_effect_states, key))

          _ ->
            # ignore the scoped state
            effect_states
        end
      end
    end)
  end

  @doc """
  Interpret effects until there is only %Pure{} remaining - does not finalize.
  Useful for Effect handlers which want to run a sub-computation and control
  the outputs (e.g. discard or commit to the parent)
  """
  @spec interpret(Freer.freer(), RunState.t()) :: {Pure.t(), RunState.t()}
  def interpret(
        %Pure{val: val} = computation,
        %RunState{} = run_state
      ) do
    # if we get to the finalize phase and no effect has decided upon
    # what type of output it's going to be, then it's an OkResult,
    # signalling a normal completion
    computation = if !Result.type(val), do: %Pure{val: %OkResult{value: val}}, else: computation

    {computation, run_state}
  end

  def interpret(
        %Impure{} = computation,
        %RunState{} = run_state
      ) do
    {new_computation, updated_run_state} = interpret_one(computation, run_state)

    interpret(new_computation, updated_run_state)
  end

  def interpret(
        sendable,
        %RunState{} = run_state
      ) do
    computation = Sendable.send(sendable)

    if computation == sendable do
      raise ArgumentError,
        message:
          "#{__MODULE__}.run - not Sendable: #{inspect(sendable, pretty: true)} - " <>
            " do you need to return() ?"
    end

    interpret(computation, run_state)
  end

  @doc """
  Interpret a single effects
  """
  @spec interpret_one(
          Freer.freer(),
          RunState.t()
        ) :: {Freer.freer(), RunState.t()}
  def interpret_one(
        %Pure{} = computation,
        %RunState{} = run_state
      ) do
    {computation, run_state}
  end

  # blessed handler for ScopedResults - it must be handled here, because
  # the EffectHandler behaviour does not support effects which can
  # change other effect's state - instead, the EffectHandler.scoped_return
  # funciton is offered, which allows handlers to override their own
  # scoped_return action
  def interpret_one(
        %Impure{
          sig: RunEffects,
          data:
            %ScopedResult{
              computation: computation
            } = scoped_result,
          q: q
        },
        %RunState{} = run_state
      ) do
    updated_effect_states = scoped_return(run_state, scoped_result)

    {
      Impl.bindp(computation, q),
      %{run_state | states: updated_effect_states}
    }
  end

  def interpret_one(
        %Impure{sig: _sig, data: _u, q: _q} = effect,
        %RunState{handlers: handlers} = run_state
      ) do
    Logger.error(
      "#{__MODULE__}.interpret_one\n" <>
        "effect: #{inspect(effect, pretty: true)}\n" <>
        "run_state: #{inspect(run_state, pretty: true)}"
    )

    {new_effect, updated_run_state} =
      handlers
      |> Enum.reduce_while({effect, run_state}, fn {key, mod}, {effect, run_state} = acc ->
        # Logger.error("#{__MODULE__}.interpret reduce\n#{inspect(effect, pretty: true)}")

        if mod.handles?(effect) do
          {new_effect, updated_state} =
            mod.interpret(effect, key, Map.get(run_state.states, key), run_state)

          # observer? handlers see but do not touch the effect - but they can
          # update their own state
          observer? = effect_equals?(new_effect, effect)
          reduce_action = if observer?, do: :cont, else: :halt

          # Logger.error(
          #   "#{__MODULE__}.post-interpret\n" <>
          #     "new_effect: #{inspect(new_effect, pretty: true)}\n"
          # )

          {reduce_action,
           {new_effect,
            %{
              run_state
              | states: Map.put(run_state.states, key, updated_state)
            }}}
        else
          {:cont, acc}
        end
      end)

    handled? = !effect_equals?(new_effect, effect)

    if !handled? do
      # TODO replace with an error effect, for nice retry/resume
      raise ArgumentError,
        message:
          "#{__MODULE__}.run: no handler for effect in stack\n" <>
            "#{inspect(effect, pretty: true)}\n" <>
            "#{inspect(run_state, pretty: true)}"
    end

    {new_effect, updated_run_state}
  end

  # is effect b different from effect a
  defp effect_equals?(b, %Impure{sig: sig, data: data, q: _q} = _a) do
    case b do
      %Impure{sig: updated_sig, data: updated_data, q: _updated_q} ->
        updated_sig == sig && updated_data == data

      _ ->
        false
    end
  end

  # put the handlers for the Freya.Run.RunEffects into a Handler module,
  # and silently add them to the _end_ of the handler list (so other handlers
  # like EffectLogger get a chance to have at the commit/discard effects)
end
