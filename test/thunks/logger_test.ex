defmodule Thunks.LoggerTest do
  use ExUnit.Case

  require Logger
  alias Thunks.Freer
  alias Thunks.Freer.{Pure, Impure}
  alias Thunks.FreerOps
  alias Thunks.EffectLogger
  alias Thunks.State

  # define constructors for a simple language with
  # - number
  # - error
  # - add operation
  # - subtract ooperation
  # - multiply operation
  # - divide operation
  defmodule NumbersGrammar do
    def number(a), do: {:number, a}
    def error(e), do: {:error, e}
    def add(a, b), do: {:add, a, b}
    def subtract(a, b), do: {:subtract, a, b}
    def multiply(a, b), do: {:multiply, a, b}
    def divide(a, b), do: {:divide, a, b}
  end

  defmodule Numbers do
    use FreerOps, ops: NumbersGrammar
  end

  # interpret the Numbers langauge with ret + handle functions
  #
  # ret and handle must return Freer structs
  #
  # - ret : wrap a plain value in a Freer<Numbers>
  # - handle : interpret a Numbers statement, either
  #  passing a plain value on to the continuation, or
  #  short-circuit returning a Freer<Numbers>
  defmodule InterpretNumbers do
    # wrap a value in a Numbers structure
    def ret(n), do: Freer.return({:number, n})

    # interpret a Numbers structure and pass a value on to
    # the continuation. The continuiation will return a Freer,
    # so handle must return a Freer too if it doesn't call
    # the continuation
    def handle({:number, n}, k), do: k.(n)
    def handle({:also_number, n}, k), do: k.(n)
    def handle({:add, a, b}, k), do: k.(a + b)
    def handle({:subtract, a, b}, k), do: k.(a - b)
    def handle({:multiply, a, b}, k), do: k.(a * b)

    def handle({:divide, a, b}, k) do
      if b != 0 do
        k.(a / b)
      else
        Freer.return({:error, "divide by zero: #{a}/#{b}"})
      end
    end

    def handle({:error, err}, _f), do: Freer.return({:error, err})
  end

  def run_numbers(fv) do
    fv
    |> Freer.handle_relay(
      [Numbers],
      &InterpretNumbers.ret/1,
      &InterpretNumbers.handle/2
    )
  end

  describe "logger handler" do
    test "it can mix numbers with the state interpretation of Reader+Writer" do
      require Freer

      fv =
        Freer.con [Numbers, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps a <- get(),
                b <- number(10),
                put(a + b),
                c <- multiply(a, b),
                d <- get() do
            subtract(d, c)
          end
        end

      result =
        fv
        |> EffectLogger.run_logger()
        |> run_numbers()
        |> Thunks.State.run_expanded(12)
        |> Freer.run()

      Logger.error("#{__MODULE__}.logger-handler\n#{inspect(result, pretty: true)}")
      assert {{:number, -98}, 22} == result
    end
  end
end
