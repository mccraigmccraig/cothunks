defmodule Freya.Effects.Reader.Constructors do
  @moduledoc "Constructors for the Reader effect"

  @doc "Get the current environment value"
  def ask(), do: :ask
end

defmodule Freya.Effects.Reader do
  @moduledoc "Operations (Ops) for the Reader effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Reader.Constructors
end

defmodule Freya.Effects.Reader.Interpreter do
  @moduledoc "Interpreter (handler) for the Reader effect"
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Pure
  alias Freya.Effects.Reader
  alias Freya.Run.RunState

  @behaviour Freya.EffectHandler

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: sig, data: _data, q: _q}) do
    sig == Reader
  end

  @impl Freya.EffectHandler
  def interpret(
        %Freer.Impure{sig: eff, data: u, q: q} = _computation,
        _handler_key,
        state,
        %RunState{} = _run_state
      ) do
    case {eff, u} do
      {Reader, :ask} ->
        {Impl.q_apply(q, state), state}

      _ ->
        {%Freer.Impure{sig: eff, data: u, q: q}, state}
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
