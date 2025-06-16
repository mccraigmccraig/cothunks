# Structured Logging System for Thunks.Freer

This document describes the structured logging system added to Thunks.Freer, which enables computation persistence, resumption, and detailed tracing of effect-based computations.

## Overview

The structured logging system provides four key capabilities:

1. **Detailed Computation Tracing**: Log all intermediate values and effects during computation
2. **JSON Persistence**: Serialize computation logs for storage and later analysis
3. **Computation Resumption**: Resume computations from saved logs, avoiding redundant work
4. **Yield/Resume Support**: Handle computations that yield control and can be resumed later

## Core Data Structures

### LogEntry

Represents a single computation step:

```elixir
%LogEntry{
  step_id: 0,                    # Unique step identifier
  timestamp: 1234567890,         # Microsecond timestamp
  effect: :math,                 # The effect being executed
  input: {:add, 5, 7},          # Input parameters to the effect
  output: 12,                    # Result of the effect
  step_type: :effect,            # :effect, :continuation, or :pure
  continuation_id: "cont_0",     # Continuation identifier
  parent_step_id: nil           # Parent step for nested effects
}
```

### ComputationLog

Maintains the complete computation history:

```elixir
%ComputationLog{
  steps: [%LogEntry{}, ...],     # List of computation steps
  current_step: 5,               # Current step counter
  status: :completed,            # :running, :completed, :yielded, :error
  result: 42,                    # Computation result (if completed)
  error: nil                     # Error information (if failed)
}
```

## Key Functions

### Basic Logging

#### `handle_with_log/2`

Runs a computation with structured logging enabled:

```elixir
{result, log} = 
  computation
  |> Freer.handle_with_log()
  |> run_effects()
  |> Freer.run()
```

#### `handle_with_log_and_state/4`

Advanced logging with custom state management:

```elixir
{result, final_log, final_state} = 
  computation
  |> Freer.handle_with_log_and_state(log, state, return_fn)
  |> run_effects()
  |> Freer.run()
```

### Persistence

#### `persist_log/1` and `load_log/1`

Save and restore computation logs:

```elixir
# Save log to JSON
{:ok, json_string} = Freer.persist_log(log)
File.write!("computation.json", json_string)

# Load log from JSON
{:ok, restored_log} = File.read!("computation.json") |> Freer.load_log()
```

### Resumption

#### `resume_computation/2`

Resume a computation from a saved log:

```elixir
{result, final_log} = 
  computation
  |> Freer.resume_computation(saved_log)
  |> run_effects()
  |> Freer.run()
```

The system automatically detects which steps have already been completed and skips them, only executing new or incomplete steps.

### Yield and Resume

#### `yield_computation/1`

Create a yield point in a computation:

```elixir
computation = 
  Freer.con [MyEffects] do
    steps a <- get_value(),
          _ <- Freer.yield_computation("checkpoint_1"),
          b <- expensive_operation() do
      combine(a, b)
    end
  end
```

#### `handle_yield/2`

Handle computations that may yield:

```elixir
{status, log} = 
  computation
  |> Freer.handle_yield()
  |> run_effects()
  |> Freer.run()

case status do
  :yielded -> 
    # Save log and resume later
    {:ok, json} = Freer.persist_log(log)
    save_checkpoint(json)
  
  result -> 
    # Computation completed normally
    handle_result(result)
end
```

## Usage Examples

### Basic Computation Logging

```elixir
defmodule MathOps do
  def number(n), do: Freer.send_effect(n, :number)
  def add(a, b), do: Freer.send_effect({:add, a, b}, :math)
  def multiply(a, b), do: Freer.send_effect({:multiply, a, b}, :math)
end

computation = 
  Freer.con [MathOps] do
    steps a <- number(10),
          b <- number(5),
          sum <- add(a, b) do
      multiply(sum, 2)
    end
  end

{result, log} = 
  computation
  |> Freer.handle_with_log()
  |> run_math_effects()
  |> Freer.run()

# result = 30
# log contains detailed trace of all steps
```

### Persistence and Resumption

```elixir
# Run computation with logging
{result, log} = run_logged_computation()

# Persist the log
{:ok, json_log} = Freer.persist_log(log)
File.write!("computation_log.json", json_log)

# Later, resume from the log
{:ok, saved_log} = File.read!("computation_log.json") |> Freer.load_log()

# This will skip already-completed steps
{resumed_result, final_log} = 
  computation
  |> Freer.resume_computation(saved_log)
  |> run_effects()
  |> Freer.run()
```

### Yield and Resume Workflow

```elixir
# Long-running computation with checkpoints
workflow = 
  Freer.con [WorkflowEffects] do
    steps data <- fetch_data(),
          _ <- Freer.yield_computation("data_fetched"),
          processed <- process_data(data),
          _ <- Freer.yield_computation("data_processed"),
          result <- save_result(processed) do
      result
    end
  end

# Handle yielding
{status, log} = 
  workflow
  |> Freer.handle_yield()
  |> run_workflow_effects()
  |> Freer.run()

case status do
  :yielded ->
    # Save progress and continue later
    save_workflow_state(log)
    schedule_continuation()
    
  result ->
    # Workflow completed
    handle_completion(result)
end
```

## Use Cases

### 1. Long-Running Process Checkpointing

For computations that take a long time or might be interrupted:

- Save progress at regular intervals
- Resume from the last checkpoint if interrupted
- Avoid repeating expensive operations

### 2. Detailed Debugging

When debugging complex effect compositions:

- Examine intermediate values at each step
- Trace the exact sequence of effects
- Identify where computations diverge from expectations

### 3. Performance Monitoring

For production systems:

- Track timing of individual effects
- Identify performance bottlenecks
- Monitor resource usage patterns

### 4. Testing and Replay

For deterministic testing:

- Record computation traces in tests
- Replay exactly the same sequence of effects
- Verify behavior under specific conditions

### 5. Distributed Computing

For distributed or cloud-based computations:

- Serialize computation state for transfer between nodes
- Resume computations on different machines
- Handle node failures gracefully

## Advanced Features

### Custom Log Initialization

Initialize logs with custom settings:

```elixir
log = ComputationLog.new()

{result, final_log} = 
  computation
  |> Freer.handle_with_log(log)
  |> run_effects()
  |> Freer.run()
```

### Log Analysis

Analyze computation logs programmatically:

```elixir
# Extract all intermediate values
intermediate_values = 
  log.steps
  |> Enum.filter(&(&1.output != nil))
  |> Enum.map(&{&1.step_id, &1.effect, &1.output})

# Calculate timing metrics
step_durations = 
  log.steps
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.map(fn [a, b] -> b.timestamp - a.timestamp end)

# Group by effect type
effect_counts = 
  log.steps
  |> Enum.group_by(&(&1.effect))
  |> Enum.map(fn {effect, steps} -> {effect, length(steps)} end)
```

### Error Recovery

Handle partial failures gracefully:

```elixir
try do
  {result, log} = run_logged_computation()
  result
rescue
  error ->
    # Examine log to see what completed successfully
    completed_steps = 
      log.steps
      |> Enum.filter(&(&1.output != nil))
    
    # Decide whether to retry from a checkpoint
    if length(completed_steps) > threshold do
      retry_from_checkpoint(log)
    else
      raise error
    end
end
```

## Integration with Existing Effects

The structured logging system works transparently with all existing Freer effects:

- **Reader**: Logs environment reads
- **Writer**: Logs output operations  
- **State**: Logs state changes
- **Coroutine**: Logs yield/resume operations
- **Custom Effects**: Logs any user-defined effects

## Performance Considerations

- Logging adds overhead to each effect execution
- Log size grows linearly with computation complexity
- JSON serialization can be expensive for large logs
- Consider using logging selectively for critical computations

## Future Enhancements

Potential improvements to the logging system:

1. **Selective Logging**: Log only specific effect types
2. **Compression**: Compress large logs for storage
3. **Streaming**: Stream logs to external systems
4. **Partial Resumption**: Resume from arbitrary points in the log
5. **Log Merging**: Combine logs from parallel computations
6. **Binary Serialization**: More efficient than JSON for large logs

## Conclusion

The structured logging system transforms Thunks.Freer into a powerful platform for building resilient, observable, and maintainable effect-based applications. It enables sophisticated workflow management, debugging, and monitoring capabilities while maintaining the composability and elegance of the underlying Freer monad architecture.