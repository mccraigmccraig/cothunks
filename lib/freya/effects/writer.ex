defmodule Freya.Effects.Writer.Constructors do
  @moduledoc "Constructors for the Writer effect"

  @doc "Output a value to the writer's log"
  def tell(o), do: {:tell, o}
end

defmodule Freya.Effects.Writer do
  @moduledoc "Operations (Ops) for the Writer effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Writer.Constructors
end

defmodule Freya.Effects.Writer.Interpreter do
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Effects.Writer

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Writer
  end

  @impl Freya.EffectHandler
  def interpret(computation, _handler_key, state, _all_states) do
    case computation do
      %Freer.Pure{val: _x} = pure ->
        {pure, state}

      %Freer.Impure{sig: eff, data: u, q: q} ->
        case {eff, u} do
          {Writer, {:tell, o}} ->
            updated_state = [o | state || []]
            {Impl.q_apply(q, updated_state), updated_state}

          _ ->
            {%Freer.Impure{sig: eff, data: u, q: q}, state}
        end
    end
  end
end
