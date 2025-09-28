defmodule Freya.EffectHandler do
  @moduledoc """
  The Run module uses EffectHandlers to interpret
  effects when running a computation
  """

  alias Freya.Freer

  @doc """
  return true if this handler can handle the given effect. Handlers
  will be offered each effect in priority-queue order.

  A Handler may choose to handle an effect, and return it unchanged
  - in which case the `updated_state` and `outputs` of the handler
  will be recorded, but the effect will continue to be offered to
  further EffectHandlers until one handles it and changes it
  """
  @callback handles?(computation :: Freer.Impure.t()) :: boolean

  @doc """
  interpret an Effect with the handler - the handler
  - handler_key - its key in the outputs
  - state - its state returned from its last invocation
  - outputs - the combined outputs of all handlers so far

  the function should return:

  `{effect, updated_state}`

  its `updated_state` will be retained and given to the next
  invocation of this handler

  """
  @callback interpret(
              computation :: Freer.freer(),
              handler_key :: atom,
              state :: any,
              all_states :: %{atom => any}
            ) :: {Freer.freer(), any}
end
