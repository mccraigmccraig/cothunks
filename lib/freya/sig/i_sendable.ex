defprotocol Freya.Sig.ISendable do
  @fallback_to_any true

  @spec send(t) :: Freya.Freer.freer()
  def send(eff)
end

defimpl Freya.Sig.ISendable, for: Any do
  def send(eff), do: eff
end
