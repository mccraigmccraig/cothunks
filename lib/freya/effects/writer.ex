defmodule Freya.Effects.Writer.Constructors do
  @moduledoc "Constructors for the Writer effect"

  @doc "Output a value to the writer's log"
  def tell(o), do: {:tell, o}
end

defmodule Freya.Effects.Writer do
  @moduledoc "Operations (Ops) for the Writer effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Writer.Constructors
end

defmodule Freya.Effects.Writer.Handler do
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Effects.Writer
  alias Freya.Run.RunState

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Writer
  end

  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: Writer, data: u, q: q} = _computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    case u do
      {:tell, o} ->
        updated_state = [o | state || []]
        {Impl.q_apply(q, updated_state), updated_state}
    end
  end

  @impl Freya.EffectHandler
  def finalize(
        %Pure{} = computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    {computation, Enum.reverse(state || [])}
  end
end
