defmodule Freya.Effects.EffectLogger do
  require Logger

  alias Freya.Freer
  alias Freya.Freer.Ops
  alias Freya.Freer.Pure
  alias Freya.Freer.Impure

  defmodule EffectLogEntry do
    defstruct effect: nil

    @type t :: %__MODULE__{effect: any}

    def new(effect) do
      %__MODULE__{effect: effect}
    end
  end

  defmodule InterpretedEffectLogEntry do
    defstruct effect: nil, value: nil

    @type t :: %__MODULE__{effect: any, value: any}

    def set_value(%EffectLogEntry{} = log_entry, value) do
      %InterpretedEffectLogEntry{effect: log_entry.effect, value: value}
    end
  end

  # cf interceptor chains
  defmodule Log do
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

    def log_effect(%__MODULE__{} = log, effect) do
      case log.queue do
        [] ->
          %{log | queue: [EffectLogEntry.new(effect)]}

        _ ->
          raise ArgumentError, message: "unexpected effect: #{inspect(effect, pretty: true)}"
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
      %Log{
        stack: [],
        queue: Enum.reverse(log.stack) ++ log.queue
      }
    end
  end

  defmodule LoggedComputation do
    defstruct result: nil, log: nil

    @type t :: %__MODULE__{
            result: any,
            log: Log.t()
          }

    def new(result, %Log{} = log) do
      %__MODULE__{result: result, log: Log.prepare_for_resume(log)}
    end
  end

  # define a private effect to capture interpreted effect values
  defmodule LogInterpretedEffectValue do
    defstruct value: nil
  end

  defmodule EffectLoggerConstructors do
    def log_interpreted_effect_value(v), do: %LogInterpretedEffectValue{value: v}
  end

  defmodule EffectLoggerOps do
    use Ops, constructors: EffectLoggerConstructors
  end

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

  def interpret_logger(computation) do
    interpret_logger(computation, Log.new())
  end

  def interpret_logger(computation, %Log{} = log) do
    # Logger.error("#{__MODULE__}.run_logger #{inspect(computation, pretty: true)}")

    case computation do
      %Pure{val: x} ->
        r =
          Freya.RunOutcome.ensure(x)
          |> Freya.RunOutcome.put(:logged_computation, LoggedComputation.new(x, log))
          |> Freya.RunOutcome.flatten()

        Freer.return(r)

      %Impure{sig: eff, data: u, q: q} ->
        case {eff, u} do
          {EffectLoggerOps, %LogInterpretedEffectValue{value: val}} ->
            # Logger.error("#{__MODULE__}.run_logger handling")
            # capturing the value of an executed effect
            updated_log = Log.log_interpreted_effect_value(log, val)
            k = Freya.Freer.Impl.q_comp(q, &interpret_logger(&1, updated_log))
            Freya.Freer.Impl.q_apply([k], val)

          _ ->
            # Logger.error("#{__MODULE__}.run_logger log_or_resume")
            log_or_resume(computation, log)
        end
    end
  end

  def log_or_resume(%Impure{sig: eff, data: u, q: q} = _computation, %Log{} = log) do
    {action, updated_log, value} =
      case log.queue do
        [] ->
          # a new effect LogEntry
          {:execute_effect, Log.log_effect(log, u), nil}

        [
          %InterpretedEffectLogEntry{
            effect: log_entry_effect,
            value: value
          } = _log_entry
          | _rest
        ]
        when u == log_entry_effect ->
          # resumed computation
          {:resume_effect, Log.consume_log_entry(log), value}

        _ ->
          raise ArgumentError, message: "Effect diverged from log: #{inspect(log, pretty: true)}"
      end

    case action do
      :execute_effect ->
        # pass the effect on to another interpreter, preparing to
        # log the interpreted value
        capture_k = fn v -> EffectLoggerOps.log_interpreted_effect_value(v) end

        k =
          q
          |> Freya.Freer.Impl.q_prepend(capture_k)
          |> Freya.Freer.Impl.q_comp(&interpret_logger(&1, updated_log))

        %Freer.Impure{sig: eff, data: u, q: [k]}

      :resume_effect ->
        # no need to execute the effect - use the logged value to feed the next
        # continuation
        k = Freya.Freer.Impl.q_comp(q, &interpret_logger(&1, updated_log))
        Freya.Freer.Impl.q_apply([k], value)
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
