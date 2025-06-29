defmodule Thunks.ComputationLog.LogEntry do
  @moduledoc """
  Represents a single computation step in the structured log.
  """
  defstruct [
    :step_id,
    :timestamp,
    :effect,
    :input,
    :output,
    # :effect, :continuation, :pure, :error
    :step_type,
    :continuation_id,
    :parent_step_id
  ]

  @type t :: %__MODULE__{
          step_id: non_neg_integer() | nil,
          timestamp: non_neg_integer() | nil,
          effect: atom() | nil,
          input: any(),
          output: any(),
          step_type: :effect | :continuation | :pure | :error | nil,
          continuation_id: String.t() | nil,
          parent_step_id: non_neg_integer() | nil
        }
end

defmodule Thunks.ComputationLog do
  @moduledoc """
  Structured log of computation steps for persistence and resumption.
  """

  alias Thunks.ComputationLog.LogEntry

  defstruct [
    # List of LogEntry
    :steps,
    # Current step counter
    :current_step,
    # :running, :completed, :yielded, :error
    :status,
    # Computation result if completed
    :result,
    # Error info if computation failed
    :error
  ]

  @type t :: %__MODULE__{
          steps: list(LogEntry.t()),
          current_step: non_neg_integer(),
          status: :running | :completed | :yielded | :error,
          result: any(),
          error: any()
        }

  def new do
    %__MODULE__{
      steps: [],
      current_step: 0,
      status: :running,
      result: nil,
      error: nil
    }
  end

  def add_step(log, step_entry) do
    %{log | steps: [step_entry | log.steps], current_step: log.current_step + 1}
  end

  def complete(log, result) do
    %{log | status: :completed, result: result}
  end

  def error(log, error_info) do
    %{log | status: :error, error: error_info}
  end

  def yield(log, yield_info) do
    %{log | status: :yielded, result: yield_info}
  end

  def to_json(log) do
    # Convert to JSON-serializable format
    serializable_log =
      log
      |> Map.from_struct()
      |> Map.update!(:steps, fn steps ->
        Enum.map(steps, fn step ->
          step
          |> Map.from_struct()
          |> Map.update!(:input, fn
            nil -> nil
            input -> inspect(input)
          end)
          |> Map.update!(:output, fn
            nil -> nil
            output -> inspect(output)
          end)
        end)
      end)
      |> Map.update!(:result, fn
        nil -> nil
        # Convert to string for JSON compatibility
        result -> inspect(result)
      end)
      |> Map.update!(:error, fn
        nil -> nil
        # Convert to string for JSON compatibility
        error -> inspect(error)
      end)

    Jason.encode(serializable_log)
  end

  def from_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} ->
        steps =
          Enum.map(data["steps"] || [], fn step ->
            struct!(LogEntry, %{
              step_id: step["step_id"],
              timestamp: step["timestamp"],
              effect: if(step["effect"], do: String.to_atom(step["effect"]), else: nil),
              input: step["input"],
              output: step["output"],
              step_type: if(step["step_type"], do: String.to_atom(step["step_type"]), else: nil),
              continuation_id: step["continuation_id"],
              parent_step_id: step["parent_step_id"]
            })
          end)

        # Parse result and error from their string representations if needed
        result =
          case data["result"] do
            nil ->
              nil

            str when is_binary(str) ->
              # In a real implementation, you might want more sophisticated deserialization
              str

            other ->
              other
          end

        error =
          case data["error"] do
            nil -> nil
            str when is_binary(str) -> str
            other -> other
          end

        {:ok,
         struct!(__MODULE__, %{
           steps: steps,
           current_step: data["current_step"] || 0,
           status: String.to_atom(data["status"] || "running"),
           result: result,
           error: error
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Persist a computation log to JSON format for later resumption.
  """
  @spec persist(t()) :: {:ok, String.t()} | {:error, any}
  def persist(log) do
    to_json(log)
  end

  @doc """
  Load a computation log from JSON format.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, any}
  def load(json_string) do
    from_json(json_string)
  end
end
