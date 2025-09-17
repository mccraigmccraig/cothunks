defprotocol Freya.Protocols.Tagged do
  @doc """
  A tag to identify an effect's state in the output Map
  """
  def tag(eff)
end
