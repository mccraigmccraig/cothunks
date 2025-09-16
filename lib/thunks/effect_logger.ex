defmodule Thunks.EffectLogger do
  require Logger

  alias Thunks.Freer
  alias Thunks.FreerOps
  alias Thunks.Freer.Pure
  alias Thunks.Freer.Impure

  defmodule InterpretedEffectLogEntry do
    defstruct effect: nil, value: nil

    @type t :: %__MODULE__{
            effect: any,
            value: any
          }
  end

  defmodule EffectLogEntry do
    defstruct effect: nil, value: nil

    @type t :: %__MODULE__{
            effect: any,
            value: any
          }

    def new(effect) do
      %__MODULE__{
        effect: effect,
        value: nil
      }
    end

    def set_value(%EffectLogEntry{} = log_entry, value) do
      %InterpretedEffectLogEntry{effect: log_entry.effect, value: value}
    end
  end

  # cf interceptor chains
  defmodule Log do
    defstruct stack: [], queue: []

    @type t :: %__MODULE__{
            stack: list(InterpretedEffectLogEntry.t()),
            queue: list(LogEntry.t() | InterpretedEffectLogEntry.t())
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

    def log_effect_value(%__MODULE__{} = log, effect_value) do
      case log.queue do
        [%EffectLogEntry{} = log_entry] ->
          %{
            log
            | stack: [EffectLogEntry.set_value(log_entry, effect_value) | log.stack],
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
  end

  defmodule LoggedComputation do
    defstruct result: nil, log: nil

    @type t :: %__MODULE__{
            result: any,
            log: Log.t()
          }

    def new(result, %Log{} = log) do
      %__MODULE__{result: result, log: log}
    end
  end

  defmodule OpsGrammar do
    def log_effect_value(v), do: {:log_effect_value, v}
  end

  defmodule Ops do
    use FreerOps, ops: OpsGrammar
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

  def run_logger(computation) do
    run_logger(computation, Log.new())
  end

  def run_logger(computation, %Log{} = log) do
    # Logger.error("#{__MODULE__}.run_logger #{inspect(computation, pretty: true)}")

    case computation do
      %Pure{val: x} ->
        Freer.return(LoggedComputation.new(x, log))

      %Impure{eff: eff, mval: u, q: q} ->
        case {eff, u} do
          {Ops, {:log_effect_value, val}} ->
            # Logger.error("#{__MODULE__}.run_logger handling")
            # capturing the value of an executed effect
            updated_log = Log.log_effect_value(log, val)
            k = Freer.q_comp(q, &run_logger(&1, updated_log))
            Freer.q_apply([k], val)

          _ ->
            # Logger.error("#{__MODULE__}.run_logger log_or_resume")
            log_or_resume(computation, log)
        end
    end
  end

  def log_or_resume(%Impure{eff: eff, mval: u, q: q} = _computation, %Log{} = log) do
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
        when eff == log_entry_effect ->
          # resumed computation
          {:resume_effect, Log.consume_log_entry(log), value}

        _ ->
          raise ArgumentError, message: "Effect diverged from log: #{inspect(log, pretty: true)}"
      end

    case action do
      :execute_effect ->
        # pass the effect on to another interpreter, preparing to
        # log the interpreted value
        capture_k = fn v -> Ops.log_effect_value(v) end

        k =
          q
          |> Freer.q_prepend(capture_k)
          |> Freer.q_comp(&run_logger(&1, updated_log))

        %Freer.Impure{eff: eff, mval: u, q: [k]}

      :resume_effect ->
        # no need to execute the effect - use the logged value to feed the next
        # continuation
        k = Freer.q_comp(q, &run_logger(&1, updated_log))
        Freer.q_apply([k], value)
    end
  end
end
