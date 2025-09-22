defmodule Freya.Effects.Finalize.Constructors do
  @moduledoc "Constructors for the Finalize effect"

  @doc "Emit a Finalize effect carrying a RunOutcome payload"
  def finalize(%Freya.RunOutcome{} = out), do: {:finalize, out}
end

defmodule Freya.Effects.Finalize do
  @moduledoc "Operations (Ops) for the Finalize effect"
  use Freya.Freer.Ops, constructors: Freya.Effects.Finalize.Constructors
end

