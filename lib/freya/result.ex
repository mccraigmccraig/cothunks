defprotocol Freya.Result do
  @fallback_to_any true

  @spec type(t) :: atom
  def type(result)

  @spec value(t) :: any
  def value(result)
end
