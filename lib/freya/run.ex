defmodule Freya.Run do
  @moduledoc """
  Functions to manage a priority-list of EffectHandlers and run a computation
  in the context of that list of EffectHandlers

  EffectHandlers are structs providing the EffectHandler protocol
  """
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Result
  alias Freya.RunOutcome

  defstruct handlers: [], states: %{}, outputs: %{}

  @type handler_mod :: atom
  @type handler_mod_with_state :: {atom, any}
  @type handler_spec :: handler_mod | handler_mod_with_state()
  @type handler_key :: atom
  @type handler_spec_list :: list({handler_key, handler_spec})

  @doc """
  Build a Run struct with the provided EffectHandlers, and their initial state
  """
  @spec with_handlers(handler_spec_list()) :: %__MODULE__{}
  def with_handlers(handler_specs) do
    handler_specs
    |> Enum.map(fn
      {key, mod} when is_atom(key) and is_atom(mod) -> {key, {mod, nil}}
      {key, {mod, _state}} = spec_with_state when is_atom(key) and is_atom(mod) -> spec_with_state
    end)
    |> Enum.reduce(
      %__MODULE__{handlers: [], states: %{}, outputs: %{}},
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
            states: %{acc.states | key => state}
        }
      end
    )
    |> then(fn %__MODULE__{handlers: handlers} = self ->
      %{self | handlers: Enum.reverse(handlers)}
    end)
  end

  @spec run(Freer.freer(), %__MODULE__{}) :: any
  def run(%Pure{val: val}, %__MODULE__{} = runner) do
    %RunOutcome{
      result: val,
      outputs: runner.outputs
    }
  end

  def run(
        %Impure{sig: _sig, data: _u, q: _q} = effect,
        %__MODULE__{
          handlers: handlers,
          states: states,
          outputs: outputs
        } = run_state
      ) do
    {new_effect, updated_run_state} =
      handlers
      |> Enum.reduce_while({effect, run_state}, fn {key, mod}, {effect, run_state} = acc ->
        if mod.handles?(effect) do
          {new_effect, updated_state, output} =
            mod.interpret(effect, key, Map.get(states, key), outputs)

          observer? = new_effect === effect
          reduce_action = if observer?, do: :cont, else: :halt

          {reduce_action,
           {new_effect,
            %{
              run_state
              | states: Map.put(states, key, updated_state),
                outputs: %{outputs: Map.put(outputs, key, output)}
            }}}
        else
          {:cont, acc}
        end
      end)

    handled? = new_effect !== effect

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
end
