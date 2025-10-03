defmodule Freya.LoggerTest do
  use ExUnit.Case

  require Logger

  import Freya.Con

  alias Freya.ErrorResult
  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Impure
  alias Freya.Freer.Ops
  alias Freya.Freer.Pure
  alias Freya.Effects.EffectLogger
  alias Freya.Effects.EffectLogger.InterpretedEffectLogEntry
  alias Freya.Effects.Reader
  alias Freya.Effects.Writer
  alias Freya.Effects.State
  alias Freya.Run
  alias Freya.Run.RunState

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
    use Ops, constructors: NumbersGrammar
  end

  # interpret the Numbers langauge with ret + handle functions
  #
  # ret and handle must return Freer structs
  #
  # - ret : wrap a plain value in a Freer<Numbers>
  # - handle : interpret a Numbers statement, either
  #  passing a plain value on to the continuation, or
  #  short-circuit returning a Freer<Numbers>
  defmodule Numbers.Handler do
    alias Freya.LoggerTest.Numbers

    @behaviour Freya.EffectHandler

    @impl Freya.EffectHandler
    def handles?(%Impure{sig: sig, data: _data, q: _q}) do
      sig == Numbers
    end

    @impl Freya.EffectHandler
    def interpret(
          %Freer.Impure{sig: Numbers, data: u, q: q} = _computation,
          _handler_key,
          _state,
          %RunState{} = _run_state
        ) do
      next =
        case u do
          {:number, n} ->
            Impl.q_apply(q, n)

          {:also_number, n} ->
            Impl.q_apply(q, n)

          {:add, a, b} ->
            Impl.q_apply(q, a + b)

          {:subtract, a, b} ->
            Impl.q_apply(q, a - b)

          {:multiply, a, b} ->
            Impl.q_apply(q, a * b)

          {:divide, a, b} ->
            if b != 0 do
              Impl.q_apply(q, a / b)
            else
              Numbers.error("divide by zero #{a}/#{b}")
            end

          {:error, err} ->
            Freer.return(ErrorResult.error(err))
        end

      {next, nil}
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

  describe "logger handler" do
    test "it can mix numbers with the state interpretation of Reader+Writer" do
      fv =
        con [Numbers, State] do
          {:foo, a} <- get()
          b <- number(10)
          x <- return(12)
          put({:bar, a + b + x})
          c <- multiply(a, b)
          {:bar, d} <- get()
          subtract(d, c)
        end

      runner =
        Run.with_handlers(
          l: EffectLogger.Handler,
          n: Numbers.Handler,
          s: {State.Handler, {:foo, 12}}
        )

      # Logger.error("#{inspect(runner, pretty: true)}\n#{inspect(fv, pretty: true)}")

      result = fv |> Run.run(runner)

      Logger.error("#{__MODULE__}.logger-handler\n#{inspect(result, pretty: true)}")

      assert %Freya.RunOutcome{
               result: %Freya.OkResult{value: final_val},
               outputs: %{
                 s: {:bar, 34},
                 l: %Freya.Effects.EffectLogger.LoggedComputation{
                   result: lc_val,
                   log: %Freya.Effects.EffectLogger.Log{stack: lc_stack, queue: lc_queue}
                 }
               }
             } = result

      # the logged computation result should match the final value
      assert lc_val == final_val
      # stack is empty after preparing for resume
      assert lc_stack == []
      # log entries are fully deterministic
      assert lc_queue == [
               %InterpretedEffectLogEntry{sig: Reader, data: :get, value: {:foo, 12}},
               %InterpretedEffectLogEntry{sig: Numbers, data: {:number, 10}, value: 10},
               %InterpretedEffectLogEntry{sig: Writer, data: {:put, {:bar, 34}}, value: nil},
               %InterpretedEffectLogEntry{sig: Numbers, data: {:multiply, 12, 10}, value: 120},
               %InterpretedEffectLogEntry{sig: Reader, data: :get, value: {:bar, 34}},
               %InterpretedEffectLogEntry{sig: Numbers, data: {:subtract, 34, 120}, value: -86}
             ]
    end
  end
end
