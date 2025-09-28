# define a private effect to capture interpreted effect values
defmodule Freya.Effects.EffectLogger.LogInterpretedEffectValue do
  defstruct value: nil
end

defmodule Freya.Effects.EffectLogger.EffectLoggerConstructors do
  alias Freya.Effects.EffectLogger.LogInterpretedEffectValue

  def log_interpreted_effect_value(v), do: %LogInterpretedEffectValue{value: v}
end

defmodule Freya.Effects.EffectLogger do
  use Freya.Freer.Ops, constructors: Freya.Effects.EffectLogger.EffectLoggerConstructors
end

defmodule Freya.Effects.EffectLogger.EffectLogEntry do
  defstruct sig: nil, data: nil

  @type t :: %__MODULE__{sig: any, data: any}

  def new(sig, data) do
    %__MODULE__{sig: sig, data: data}
  end
end

defmodule Freya.Effects.EffectLogger.InterpretedEffectLogEntry do
  alias Freya.Effects.EffectLogger.EffectLogEntry

  defstruct sig: nil, data: nil, value: nil

  @type t :: %__MODULE__{sig: any, data: any, value: any}

  def set_value(%EffectLogEntry{} = log_entry, value) do
    %__MODULE__{sig: log_entry.sig, data: log_entry.data, value: value}
  end
end

# cf interceptor chains
defmodule Freya.Effects.EffectLogger.Log do
  alias Freya.Effects.EffectLogger.EffectLogEntry
  alias Freya.Effects.EffectLogger.InterpretedEffectLogEntry
  alias Freya.Freer.Pure
  alias Freya.Freer.Impure

  defstruct stack: [], queue: []

  @type t :: %__MODULE__{
          stack: list(InterpretedEffectLogEntry.t()),
          queue: list(EffectLogEntry.t() | InterpretedEffectLogEntry.t())
        }

  def new() do
    %__MODULE__{
      stack: [],
      queue: []
    }
  end

  def log_effect(%__MODULE__{} = log, %Impure{sig: sig, data: data}) do
    case log.queue do
      [] ->
        %{log | queue: [EffectLogEntry.new(sig, data)]}

      _ ->
        raise ArgumentError,
          message: "unexpected effect: #{inspect(%{sig: sig, data: data}, pretty: true)}"
    end
  end

  def log_interpreted_effect_value(%__MODULE__{} = log, effect_value) do
    case log.queue do
      [%EffectLogEntry{} = log_entry] ->
        %{
          log
          | stack: [InterpretedEffectLogEntry.set_value(log_entry, effect_value) | log.stack],
            queue: []
        }

      _ ->
        raise ArgumentError, message: "unexpected effect value: #{inspect(log, pretty: true)}"
    end
  end

  def consume_log_entry(%__MODULE__{} = log) do
    case log.queue do
      [%InterpretedEffectLogEntry{} = log_entry | rest] ->
        %{
          log
          | stack: [log_entry | log.stack],
            queue: rest
        }
    end
  end

  def prepare_for_resume(%__MODULE__{} = log) do
    %__MODULE__{
      stack: [],
      queue: Enum.reverse(log.stack) ++ log.queue
    }
  end
end

defmodule Freya.Effects.EffectLogger.LoggedComputation do
  defstruct result: nil, log: nil

  alias Freya.Effects.EffectLogger.Log

  @type t :: %__MODULE__{
          result: any,
          log: Log.t()
        }

  def new(result, %Log{} = log) do
    %__MODULE__{result: result, log: Log.prepare_for_resume(log)}
  end
end

defmodule Freya.Effects.EffectLogger.Interpreter do
  require Logger

  alias Freya.Freer
  alias Freya.Freer.Impl
  alias Freya.Freer.Pure
  alias Freya.Freer.Impure
  alias Freya.Effects.EffectLogger
  alias Freya.Effects.EffectLogger.Log
  alias Freya.Effects.EffectLogger.LogInterpretedEffectValue
  alias Freya.Effects.EffectLogger.InterpretedEffectLogEntry

  @behaviour Freya.EffectHandler

  # logger captures effects in log-queue/log-stack, and avoids repeat work
  #
  # - if the effect matches the head of the queue,
  #   - and theres a value, then
  #     - put the log-entry on the stack, and
  #     - handle the effect withe the value
  #   - if there's no value, we
  #     - leave the log-entry at the head of the queue
  #     - put a handler at the head of the chain to capture
  #       the value
  # - if the effect doesn't match the head of the queue
  #   - return an error effect - uncontrolled side-effects
  # - if the queue is empty,
  #   - add a log-entry to the head with the effect
  #   - put a handler at the head of the chain to capture the value
  #
  #
  # - if the effect is pure ??
  #   - reverse the stack and set it as the queue
  #
  # - how do logs compose ?

  @impl Freya.EffectHandler
  def handles?(%Impure{sig: _sig, data: _data, q: _q}) do
    # capture everything
    true
  end

  @impl Freya.EffectHandler
  def interpret(computation, _handler_key, log, _all_states) do
    log || Log.new()
    # Logger.error("#{__MODULE__}.run_logger #{inspect(computation, pretty: true)}")

    case computation do
      %Pure{val: x} = pure ->
        Logger.error("#{__MODULE__}.interprety_logger(%Pure{}) #{inspect(x, pretty: true)}")

        {pure, log}

      %Impure{sig: eff, data: u, q: q} ->
        Logger.error(
          "#{__MODULE__}.interprety_logger(%Impure{}) #{inspect(computation, pretty: true)}"
        )

        case {eff, u} do
          {EffectLogger, %LogInterpretedEffectValue{value: val}} ->
            # Logger.error("#{__MODULE__}.run_logger handling")
            # capturing the value of an executed effect
            updated_log = Log.log_interpreted_effect_value(log, val)
            {Impl.q_apply(q, val), updated_log}

          _ ->
            # Logger.error("#{__MODULE__}.run_logger log_or_resume")
            log_or_resume(computation, log)
        end
    end
  end

  def log_or_resume(%Impure{sig: sig, data: u, q: q} = computation, %Log{} = log) do
    {action, updated_log, value} =
      case log.queue do
        [] ->
          # a new effect LogEntry
          {:execute_effect, Log.log_effect(log, computation), nil}

        [
          %InterpretedEffectLogEntry{
            sig: log_entry_sig,
            data: log_entry_data,
            value: value
          } = _log_entry
          | _rest
        ]
        when sig == log_entry_sig and u == log_entry_data ->
          # resumed computation
          {:resume_effect, Log.consume_log_entry(log), value}

        _ ->
          raise ArgumentError, message: "Effect diverged from log: #{inspect(log, pretty: true)}"
      end

    case action do
      :execute_effect ->
        # pass the effect on to another interpreter, preparing to
        # log the interpreted value
        capture_k = fn v -> EffectLogger.log_interpreted_effect_value(v) end

        updated_q = q |> Freya.Freer.Impl.q_prepend(capture_k)

        {%Freer.Impure{sig: sig, data: u, q: updated_q}, updated_log}

      :resume_effect ->
        {Freya.Freer.Impl.q_apply(q, value), updated_log}
    end
  end
end

# ok, this seems to work pretty well... the qeustion now is
# how to deal with the log
#
# the EffectLogger needs to be the first effect in the chain,
# otherwise it doesn't see the other effects
#
# which also means that the log is deeply nested in the result
#
# maybe need something to take apart the result ?
