defmodule Thunks.FreerLoggingTest do
  use ExUnit.Case
  doctest Thunks.Freer

  alias Thunks.Freer
  alias Thunks.Freer.{ComputationLog, LogEntry}

  # Mock effect modules for testing
  defmodule TestEffects do
    def number(n), do: Freer.send_effect(n, :number)
    def add(a, b), do: Freer.send_effect({:add, a, b}, :math)
    def multiply(a, b), do: Freer.send_effect({:multiply, a, b}, :math)
    def divide(a, b), do: Freer.send_effect({:divide, a, b}, :math)
  end

  defmodule TestHandlers do
    def run_numbers(computation) do
      Freer.handle_relay(
        computation,
        [:number],
        &Freer.return/1,
        fn n, k -> k.(n) end
      )
    end

    def run_math(computation) do
      Freer.handle_relay(
        computation,
        [:math],
        &Freer.return/1,
        fn
          {:add, a, b}, k -> k.(a + b)
          {:multiply, a, b}, k -> k.(a * b)
          {:divide, a, b}, k when b != 0 -> k.(a / b)
          {:divide, _a, 0}, _k -> raise "Division by zero"
        end
      )
    end
  end

  describe "ComputationLog" do
    test "creates new log with default values" do
      log = ComputationLog.new()
      assert log.steps == []
      assert log.current_step == 0
      assert log.status == :running
      assert log.final_result == nil
      assert log.error == nil
      assert log.metadata == %{}
    end

    test "creates new log with metadata" do
      metadata = %{session_id: "test-123", user: "alice"}
      log = ComputationLog.new(metadata)
      assert log.metadata == metadata
    end

    test "adds steps to log" do
      log = ComputationLog.new()

      entry = %LogEntry{
        step_id: 0,
        timestamp: :os.system_time(:microsecond),
        effect: :number,
        input: 42,
        output: 42,
        step_type: :effect
      }

      updated_log = ComputationLog.add_step(log, entry)
      assert length(updated_log.steps) == 1
      assert updated_log.current_step == 1
      assert hd(updated_log.steps) == entry
    end

    test "marks log as completed" do
      log = ComputationLog.new()
      result = {:ok, 42}
      completed_log = ComputationLog.complete(log, result)

      assert completed_log.status == :completed
      assert completed_log.final_result == result
    end

    test "marks log as errored" do
      log = ComputationLog.new()
      error_info = %{error: "Division by zero", step: 5}
      errored_log = ComputationLog.error(log, error_info)

      assert errored_log.status == :error
      assert errored_log.error == error_info
    end

    test "marks log as yielded" do
      log = ComputationLog.new()
      yield_info = %{value: "checkpoint", step: 3}
      yielded_log = ComputationLog.yield(log, yield_info)

      assert yielded_log.status == :yielded
      assert yielded_log.metadata.yield_info == yield_info
    end
  end

  describe "JSON serialization" do
    test "serializes and deserializes log correctly" do
      log = ComputationLog.new(%{test: "data"})

      entry = %LogEntry{
        step_id: 0,
        timestamp: 1_234_567_890,
        effect: :number,
        input: 42,
        output: 42,
        step_type: :effect,
        continuation_id: "cont_0",
        parent_step_id: nil
      }

      log_with_step = ComputationLog.add_step(log, entry)
      completed_log = ComputationLog.complete(log_with_step, 42)

      {:ok, json_string} = ComputationLog.to_json(completed_log)
      assert is_binary(json_string)

      {:ok, deserialized_log} = ComputationLog.from_json(json_string)

      assert deserialized_log.current_step == completed_log.current_step
      assert deserialized_log.status == completed_log.status
      # final_result is converted to string for JSON compatibility
      assert deserialized_log.final_result == "42"
      # metadata gets converted to string keys during JSON serialization
      assert deserialized_log.metadata == %{"test" => "data"}
      assert length(deserialized_log.steps) == length(completed_log.steps)
    end

    test "handles invalid JSON gracefully" do
      invalid_json = "{invalid json"
      assert {:error, _reason} = ComputationLog.from_json(invalid_json)
    end
  end

  describe "handle_with_log" do
    test "logs pure computation" do
      import TestEffects

      computation = Freer.return(42)

      {result, log} =
        computation
        |> Freer.handle_with_log()
        |> Freer.run()

      assert result == 42
      assert length(log.steps) == 1
      assert log.status == :completed

      step = hd(log.steps)
      assert step.effect == :pure
      assert step.output == 42
    end

    test "logs simple effect computation" do
      import TestEffects

      computation = number(42)

      {result, log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> Freer.run()

      assert result == 42
      # Effect + continuation steps
      assert length(log.steps) >= 2
      assert log.status == :completed
    end

    test "logs multi-step computation" do
      import TestEffects

      computation =
        Freer.con [TestEffects] do
          steps a <- number(10),
                b <- number(20),
                sum <- add(a, b) do
            multiply(sum, 2)
          end
        end

      {result, log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()

      # (10 + 20) * 2
      assert result == 60
      # Multiple effects and continuations
      assert length(log.steps) > 4
      assert log.status == :completed

      # Verify that we have the expected effects logged
      effects = Enum.map(log.steps, & &1.effect)
      assert :number in effects
      assert :math in effects
    end
  end

  describe "computation resumption" do
    test "can resume from a completed log" do
      import TestEffects

      # Create and complete a computation
      computation = number(42)

      {result, completed_log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> Freer.run()

      # Try to resume - should return the cached result
      {resumed_result, _log} =
        computation
        |> Freer.resume_computation(completed_log)
        |> Freer.run()

      assert resumed_result == result
    end

    test "persists and loads computation log" do
      import TestEffects

      computation =
        Freer.con [TestEffects] do
          steps a <- number(5),
                b <- number(7) do
            add(a, b)
          end
        end

      {result, log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()

      # Persist the log
      {:ok, json_string} = Freer.persist_log(log)
      assert is_binary(json_string)

      # Load the log
      {:ok, loaded_log} = Freer.load_log(json_string)

      assert loaded_log.current_step == log.current_step
      assert loaded_log.status == log.status
      # final_result gets converted to string during JSON serialization
      assert loaded_log.final_result == "12"
      assert length(loaded_log.steps) == length(log.steps)
    end
  end

  describe "yield handling" do
    test "handles yield effects" do
      import TestEffects

      computation =
        Freer.con [TestEffects] do
          steps a <- number(10),
                _ <- Freer.yield_computation("checkpoint"),
                b <- number(20) do
            add(a, b)
          end
        end

      {status, log} =
        computation
        |> Freer.handle_yield()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()

      assert status == :yielded
      assert log.status == :yielded
      assert log.metadata.yield_info.yield_value == "checkpoint"
    end
  end

  describe "error handling in logging" do
    test "logs computation that errors" do
      import TestEffects

      computation =
        Freer.con [TestEffects] do
          steps a <- number(10),
                b <- number(0) do
            # This will cause an error
            divide(a, b)
          end
        end

      assert_raise RuntimeError, "Division by zero", fn ->
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()
      end
    end
  end

  describe "log inspection and analysis" do
    test "can inspect intermediate values from log" do
      import TestEffects

      computation =
        Freer.con [TestEffects] do
          steps a <- number(3),
                b <- number(4),
                c <- multiply(a, b) do
            add(c, 1)
          end
        end

      {result, log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()

      # 3 * 4 + 1
      assert result == 13

      # Extract all intermediate values from the log
      intermediate_values =
        log.steps
        |> Enum.filter(&(&1.output != nil))
        |> Enum.map(& &1.output)

      # Should contain the numbers 3, 4, intermediate result 12, and final 13
      assert 3 in intermediate_values
      assert 4 in intermediate_values
      assert 12 in intermediate_values
      assert 13 in intermediate_values
    end

    test "tracks computation timing" do
      import TestEffects

      computation = number(42)

      {_result, log} =
        computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> Freer.run()

      # All steps should have timestamps
      timestamps = Enum.map(log.steps, & &1.timestamp)
      assert Enum.all?(timestamps, &(&1 != nil))
      assert Enum.all?(timestamps, &is_integer/1)
    end
  end

  describe "advanced logging scenarios" do
    test "handles nested computations with proper step tracking" do
      import TestEffects

      # Create a computation that uses the result of another computation
      inner_computation =
        Freer.con [TestEffects] do
          steps a <- number(2),
                b <- number(3) do
            multiply(a, b)
          end
        end

      outer_computation =
        Freer.con [TestEffects] do
          steps inner_result <- inner_computation,
                c <- number(4) do
            add(inner_result, c)
          end
        end

      {result, log} =
        outer_computation
        |> Freer.handle_with_log()
        |> TestHandlers.run_numbers()
        |> TestHandlers.run_math()
        |> Freer.run()

      # (2 * 3) + 4
      assert result == 10
      # Should have multiple steps
      assert length(log.steps) > 4
      assert log.status == :completed
    end

    test "handles computation with metadata" do
      import TestEffects

      metadata = %{
        session_id: "test-session-123",
        user_id: "alice",
        computation_type: "math_ops"
      }

      log = ComputationLog.new(metadata)
      computation = number(42)

      {_result, final_log} =
        computation
        |> Freer.handle_with_log(log)
        |> TestHandlers.run_numbers()
        |> Freer.run()

      assert final_log.metadata == metadata
    end
  end
end
