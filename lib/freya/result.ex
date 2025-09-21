defprotocol Freya.Result do
  @spec type(t) :: atom
  def type(result)

  @spec value(t) :: any
  def value(result)
end
