defprotocol Freya.Protocols.Result do
  @fallback_to_any true

  @spec type(t) :: atom
  def type(result)

  @spec value(t) :: any
  def value(result)

  @spec short_circuits?(t) :: boolean
  def short_circuits?(result)
end
