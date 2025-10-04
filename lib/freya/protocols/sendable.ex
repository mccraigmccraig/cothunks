defprotocol Freya.Protocols.Sendable do
  @fallback_to_any true

  @spec send(t) :: Freya.Freer.freer()
  def send(eff)
end

defimpl Freya.Protocols.Sendable, for: Any do
  def send(eff), do: eff
end
