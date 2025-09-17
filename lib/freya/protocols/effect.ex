defprotocol Freya.Protocols.Effect do
  @doc """
  A value to uniquely identify an effect to a handler
  """
  def id(eff)
end
