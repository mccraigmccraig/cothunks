defmodule Freya.Run do
  @moduledoc """
  Functions to manage a priority-list of EffectHandlers and run a computation
  in the context of that list of EffectHandlers

  EffectHandlers are structs providing the EffectHandler protocol
  """
  alias Freya.Freer.Impure
  alias Freya.OkResult
  alias Freya.Freer.Pure
  alias Freya.Protocols.Result
  alias Freya.Run.RunState
  alias Freya.RunOutcome

  require Logger

  @type handler_mod_with_state :: {RunState.handler_key(), any}
  @type handler_spec :: RunState.handler_mod() | handler_mod_with_state()
  @type handler_spec_list :: list({RunState.handler_key(), handler_spec})

  @doc """
  Build a Run struct with the provided EffectHandlers, and their initial state
  """
  @spec with_handlers(handler_spec_list()) :: %RunState{}
  def with_handlers(handler_specs) do
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

  @spec run(Freer.freer(), %RunState{}) :: any
  def run(
        %Pure{val: val} = pure,
        %RunState{
          handlers: handlers
        } = run_state
      ) do
    # if we get to the output phase and no effect has decided upon
    # what type of output it's going to be, then it's an OkResult,
    # signalling a normal completion
    pure = if !Result.type(val), do: %Pure{val: %OkResult{value: val}}, else: pure

    # should all effects get a shot at the result ? maybe not
    {%Pure{val: final_val}, final_run_state} =
      handlers
      |> Enum.reduce({pure, run_state}, fn {key, mod}, {pure, run_state} ->
        # Logger.error("#{inspect(pure)}\n#{inspect(key)}\n#{inspect(states)}")
        {pure, updated_state} = mod.finalize(pure, key, Map.get(run_state.states, key), run_state)
        {pure, %{run_state | states: Map.put(run_state.states, key, updated_state)}}
      end)

    %RunOutcome{
      result: final_val,
      outputs: final_run_state.states
    }
  end

  def run(
        %Impure{sig: _sig, data: _u, q: _q} = effect,
        %RunState{handlers: handlers} = run_state
      ) do
    # Logger.error(
    #   "#{__MODULE__}.run\n" <>
    #     "effect: #{inspect(effect, pretty: true)}\n" <>
    #     "run_state: #{inspect(run_state, pretty: true)}"
    # )

    {new_effect, updated_run_state} =
      handlers
      |> Enum.reduce_while({effect, run_state}, fn {key, mod}, {effect, run_state} = acc ->
        # Logger.error(inspect(effect, pretty: true))

        if mod.handles?(effect) do
          {new_effect, updated_state} =
            mod.interpret(effect, key, Map.get(run_state.states, key), run_state)

          # observer? handlers see but do not touch
          observer? = !effect_changed?(new_effect, effect)
          reduce_action = if observer?, do: :cont, else: :halt

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

    handled? = effect_changed?(new_effect, effect)

    if !handled? do
      # TODO replace with an error effect, for nice retry/resume
      raise ArgumentError,
        message:
          "#{__MODULE__}.run: no handler for effect in stack\n" <>
            "#{inspect(effect, pretty: true)}\n" <>
            "#{inspect(run_state, pretty: true)}"
    else
      run(new_effect, updated_run_state)
    end
  end

  # is effect b different from effect a
  defp effect_changed?(b, %Impure{sig: sig, data: data, q: _q} = _a) do
    case b do
      %Impure{sig: updated_sig, data: updated_data, q: _updated_q} ->
        updated_sig != sig || updated_data != data

      _ ->
        true
    end
  end
end
