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

  def run(%Impure{sig: sig, data: u, q: q}, %__MODULE__{} = runner) do
  end
end
