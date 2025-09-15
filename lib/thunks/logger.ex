defmodule Thunks.Logger do
  alias Thunks.Freer
  alias Thunks.Freer.Pure
  alias Thunks.Freer.Impure

  defmodule LogEntry do
    defstruct effect: nil, awaiting_value: true, value: nil

    @type t :: %__MODULE__{
            effect: any,
            awaiting_value: boolean,
            value: any
          }

    def new(effect) do
      %__MODULE__{
        effect: effect,
        awaiting_value: true,
        value: nil
      }
    end

    def set_value(%__MODULE__{awaiting_value: true} = log_entry, value) do
      %{log_entry | awaiting_value: false, value: value}
    end
  end

  # cf interceptor chains
  defmodule Log do
    defstruct stack: [], queue: []

    @type t :: %__MODULE__{
            stack: list(LogEntry.t()),
            queue: list(LogEntry.t())
          }
  end

  def run(_computation) do
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
  def run(%Pure{val: val} = _computation, %Log{} = log) do
    ret(log).(val)
  end

  def run(%Impure{eff: eff, mval: u, q: q} = _computation, %Log{} = log) do
    {action, updated_log, value} =
      case log.queue do
        [] ->
          # first seen
          {:execute_effect, %{log | queue: [LogEntry.new(u)]}, nil}

        [
          %LogEntry{
            effect: log_entry_effect,
            awaiting_value: false,
            value: value
          } = log_entry
          | rest
        ]
        when eff == log_entry_effect ->
          # resumed computation
          {:resume_effect, %{log | stack: [log_entry | log.stack], queue: rest}, value}

        _ ->
          raise ArgumentError, message: "Effect diverged from log: #{inspect(log, pretty: true)}"
      end

    case action do
      :execute_effect ->
        # pass
        # k = fn log -> Freer.q_comp(q, &run(&1, log)) end
        # handle(updated_log).(u, store_result_k)
        nil

      :resume_effect ->
        # use the logged value to feed the next continuation
        Freer.q_apply(q, value)
    end
  end

  defp ret(log) do
    fn x ->
      updated_log =
        case log.queue do
          # there's an effect with no value at the head of the queue. now
          # we have the value. complete the LogEntry and move it to the stack
          [%LogEntry{awaiting_value: awaiting_value} = log_entry | rest]
          when awaiting_value ->
            %{
              stack: [LogEntry.set_value(log_entry, x) | log.stack],
              queue: rest
            }

          _ ->
            raise ArgumentError, message: "unexpected Pure: #{inspect(log, pretty: true)}"
        end

      Freer.return({x, updated_log})
    end
  end

  defp handle(log) do
    fn u, _k ->
      {_action, _updated_log} =
        case log.queue do
          [] ->
            {:execute_effect, %{log | queue: [LogEntry.new(u)]}}

          [%LogEntry{effect: _effect, awaiting_value: false, value: _value} = log_entry | rest] ->
            {:short_circuit_effect, %{log | stack: [log_entry | log.stack], queue: rest}}

          _ ->
            raise ArgumentError, message: "unexpected Effect: #{inspect(log, pretty: true)}"
        end
    end
  end
end
