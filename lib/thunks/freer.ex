defmodule Thunks.Freer do
  alias Thunks.ComputationLog
  alias Thunks.ComputationLog.LogEntry

  @moduledoc """
  A Freer Monad with extensible effects, based on the paper:
  https://okmij.org/ftp/Haskell/extensible/more.pdf

  with some Elixir inspiration from:
  https://github.com/aemaeth-me/freer
  https://github.com/bootstarted/effects
  """
  require Logger

  alias Thunks.Freer

  @doc """
  con - profitable cheating - and `with` in Spanish
  """
  defmacro con(mod_or_mods, do: body) do
    imports = expand_imports(mod_or_mods)

    quote do
      unquote_splicing(imports)
      unquote(Macro.postwalk(body, &steps/1))
    end
  end

  defp expand_imports(mods) when is_list(mods) do
    mods
    |> Enum.map(fn mod ->
      quote do
        import unquote(mod)
      end
    end)
  end

  defp expand_imports(mod) do
    expand_imports([mod])
  end

  defp steps({:steps, ctx, [{:<-, _ctx, [lhs, rhs]} | exprs]}) do
    binder(lhs, rhs, steps({:steps, ctx, exprs}))
  end

  defp steps({:steps, _ctx, [[do: expr] | []]}) do
    quote do
      unquote(expr)
    end
  end

  defp steps({:steps, ctx, [expr | exprs]}) do
    binder(
      quote do
        _
      end,
      expr,
      steps({:steps, ctx, exprs})
    )
  end

  defp steps(x), do: x

  defp binder(lhs, rhs, body) do
    quote do
      unquote(rhs)
      |> Freer.bind(fn unquote(lhs) -> unquote(body) end)
    end
  end

  # Freer values are %Pure{} and %Impure{}

  defmodule Pure do
    defstruct val: nil
  end

  defmodule Impure do
    defstruct eff: nil, mval: nil, q: []
  end

  @type freer() :: %Pure{} | %Impure{}

  # defp freer?(%Pure{}), do: true
  # defp freer?(%Impure{}), do: true
  # defp freer?(_), do: false

  # now the Freer functions

  @spec pure(any) :: freer
  def pure(x), do: %Pure{val: x}

  @spec send_effect(any, atom) :: freer
  def send_effect(fa, eff) do
    Logger.info("send_effect: #{inspect(fa)}, #{inspect(eff)}")
    %Impure{eff: eff, mval: fa, q: [&Freer.pure/1]}
  end

  @spec return(any) :: freer
  def return(x), do: pure(x)

  @spec bind(freer, (any -> freer)) :: freer
  def bind(%Pure{val: x}, k), do: k.(x)
  def bind(%Impure{eff: eff, mval: u, q: q}, k), do: %Impure{eff: eff, mval: u, q: q_append(q, k)}

  @doc """
  add a continuation `mf` to a queue of continuations `q`
  """
  @spec q_append([(any -> freer)], (any -> freer)) :: [(any -> freer)]
  def q_append(q, mf) do
    Enum.concat(q, [mf])
  end

  @doc """
  concatenate two queues of continuations
  """
  @spec q_concat([(any -> freer)], [(any -> freer)]) :: [(any -> freer)]
  def q_concat(qa, qb) do
    Enum.concat(qa, qb)
  end

  @doc """
  apply value `x` to a queue `q` of continuations, returning a Freer value

  applies a value throught the list of continuations until it gets an %Impure{}
  result, then adds any remaining continuations from `q` to the queue of
  that %Impure{}
  """
  @spec q_apply([(any -> freer)], any) :: freer
  def q_apply(q, x) do
    Logger.info("apply: #{inspect(x)}")

    case q do
      [k] -> k.(x)
      [k | t] -> bindp(k.(x), t)
    end
  end

  @doc """
  bind continuation queue `k` to Freer value `mx`, returning a new `Freer` value
  with the continuation queues concatenated
  """
  @spec bindp(freer, [(any -> freer)]) :: freer
  def bindp(mx, k) do
    case mx do
      %Pure{val: y} ->
        # Logger.warning("Pure apply: #{inspect(y)}")

        q_apply(k, y)

      %Impure{eff: eff, mval: u, q: q} ->
        # Logger.warning("Impure apply: #{inspect(u)}")

        %Impure{eff: eff, mval: u, q: q_concat(q, k)}
    end
  end

  @doc """
  return a new contiuation `x->Freer` which composes the
  `(freer -> freer)` function `h` with the _application_ of the
  queue of continuations `g`
  """
  @spec q_comp([(any -> freer)], (freer -> freer)) :: (any -> freer)
  def q_comp(g, h) do
    Logger.info("q_comp: #{inspect(g)} #{inspect(h)}")

    fn x ->
      q_apply(g, x) |> h.()
    end
  end

  # can the effect `eff` be handled ?
  defp handles?(effs, eff) when is_list(effs) do
    Enum.member?(effs, eff)
  end

  defp handles?(f, eff) when is_function(f, 1) do
    f.(eff)
  end

  @doc """
  Aloows easy implementation of interpreters with `ret` and `h` functions

  handle_relay must return a Freer struct
  """
  @spec handle_relay(freer, [atom], (any -> freer), (any, (any -> freer) -> freer)) :: freer
  def handle_relay(%Pure{val: x}, _effs_or_fn, ret, _h) do
    # Logger.warning("handle %Pure{}: #{inspect(x)}")
    ret.(x)
  end

  def handle_relay(%Impure{eff: eff, mval: u, q: q}, effs_or_fn, ret, h) do
    # a continuation including this handler
    k = q_comp(q, &handle_relay(&1, effs_or_fn, ret, h))

    if handles?(effs_or_fn, eff) do
      # Logger.warning("handle %Impure{}: #{inspect(u)}")
      # we can handle this effect
      h.(u, k)
    else
      # Logger.warning("NOT handling %Impure{}: #{inspect(u)}")
      # we can't handle this particular effect, just update the continuation
      # with this handler
      %Impure{eff: eff, mval: u, q: [k]}
    end
  end

  @doc """
  Allows easy implementation of interpreters which maintain state - such as the
  classical State effect. Adapted from the freer-simple implementation
  """
  @spec handle_relay_s(freer, [atom], any, (any -> freer), (any, (any -> freer) -> freer)) ::
          freer
  def handle_relay_s(%Pure{val: x}, _effs_or_fn, initial_state, ret, _h) do
    ret.(initial_state).(x)
  end

  def handle_relay_s(%Impure{eff: eff, mval: u, q: q}, effs_or_fn, initial_state, ret, h) do
    # a continuation including this handler
    k = fn s -> q_comp(q, &handle_relay_s(&1, effs_or_fn, s, ret, h)) end

    if handles?(effs_or_fn, eff) do
      # Logger.warning("handle %Impure{}: #{inspect(u)}")
      # we can handle this effect
      h.(initial_state).(u, k)
    else
      # Logger.warning("NOT handling %Impure{}: #{inspect(u)}")
      # we can't handle this particular effect, just update the continuation
      # with this handler
      %Impure{eff: eff, mval: u, q: [k.(initial_state)]}
    end
  end

  @doc """
  after all effects are handled, only %Pure{} is left
  """
  @spec run(freer) :: any
  def run(%Pure{val: x}), do: x

  def run(%Impure{eff: eff, mval: _u, q: _q} = impure) do
    raise "unhandled effect: #{eff} - #{inspect(impure)}"
  end

  ###############################
  #

  # trying out a handler which just logs and passes on
  # to the next handler... maybe we could use such a handler
  # to implement log/resume ?
  def handle_all(%Freer.Pure{} = pure_val) do
    Logger.warning("handle_all: #{inspect(pure_val)}")
    pure_val
  end

  def handle_all(%Freer.Impure{eff: eff, mval: u, q: q} = impure_val) do
    Logger.warning("handle_all: #{inspect(impure_val)}")

    inspect_val_f = fn x ->
      Logger.warning("inspect_val: #{inspect(x)}")
      Freer.return(x)
    end

    # a continuation including this handler
    k = Freer.q_comp([inspect_val_f | q], &handle_all(&1))

    %Freer.Impure{eff: eff, mval: u, q: [k]}
  end

  @doc """
  A stateful version of handle_all that maintains state while logging all computations.
  Similar to handle_relay_s but logs everything and passes all effects through unchanged.
  The state is threaded through the computation but not used for interpretation.
  """
  @spec handle_all_s(freer, any, (any -> (any -> freer))) :: freer
  def handle_all_s(%Freer.Pure{val: x} = pure_val, state, ret) do
    Logger.warning("handle_all_s Pure: #{inspect(pure_val)}, state: #{inspect(state)}")
    ret.(state).(x)
  end

  def handle_all_s(%Freer.Impure{eff: eff, mval: u, q: q} = impure_val, state, ret) do
    Logger.warning("handle_all_s Impure: #{inspect(impure_val)}, state: #{inspect(state)}")

    inspect_val_f = fn s ->
      fn x ->
        Logger.warning("inspect_val_s: #{inspect(x)}, state: #{inspect(s)}")
        Freer.return(x)
      end
    end

    # a continuation including this handler with state threading
    k = fn s -> Freer.q_comp([inspect_val_f.(s) | q], &handle_all_s(&1, s, ret)) end

    # Always pass the effect through unchanged, but thread the state
    %Freer.Impure{eff: eff, mval: u, q: [k.(state)]}
  end

  @doc """
  Convenience wrapper for handle_all_s with default return function.
  Returns a tuple of {final_value, final_state}.
  """
  @spec handle_all_s(freer, any) :: freer
  def handle_all_s(computation, initial_state) do
    handle_all_s(computation, initial_state, fn s -> fn x -> Freer.return({x, s}) end end)
  end

  @doc """
  Enhanced handler with structured logging for computation persistence and resumption.
  Maintains a ComputationLog that tracks all intermediate values and effects.

  Returns a tuple of {result, computation_log}.
  """
  @spec handle_with_log(freer, ComputationLog.t()) :: freer
  def handle_with_log(computation, log \\ ComputationLog.new()) do
    handle_with_log(computation, log, fn final_log ->
      fn result -> Freer.return({result, final_log}) end
    end)
  end

  @doc """
  Enhanced handler with structured logging that supports resumption.
  Can resume from a previous log if provided, avoiding recomputation of logged steps.

  Returns a tuple of {result, final_log}.
  """
  @spec handle_with_log(freer, ComputationLog.t(), (ComputationLog.t() ->
                                                      (any -> freer))) :: freer
  def handle_with_log(%Freer.Pure{val: x}, log, ret) do
    timestamp = :os.system_time(:microsecond)

    log_entry = %LogEntry{
      step_id: log.current_step,
      timestamp: timestamp,
      effect: :pure,
      input: nil,
      output: x,
      step_type: :pure,
      continuation_id: nil,
      parent_step_id: nil
    }

    final_log =
      log
      |> ComputationLog.add_step(log_entry)
      |> ComputationLog.complete(x)

    ret.(final_log).(x)
  end

  def handle_with_log(%Freer.Impure{eff: eff, mval: u, q: q}, log, ret) do
    timestamp = :os.system_time(:microsecond)

    # Check if we can resume from log
    case try_resume_from_log(log, eff, u) do
      {:resume, cached_result, updated_log} ->
        # We have a cached result, continue with it
        Logger.info("Resuming from log: effect #{eff}, cached result: #{inspect(cached_result)}")

        q_apply(q, cached_result)
        |> handle_with_log(updated_log, ret)

      :continue ->
        # No cached result, proceed normally
        log_entry = %LogEntry{
          step_id: log.current_step,
          timestamp: timestamp,
          effect: eff,
          input: u,
          # Will be filled when effect is resolved
          output: nil,
          step_type: :effect,
          continuation_id: "cont_#{log.current_step}",
          parent_step_id: nil
        }

        updated_log = ComputationLog.add_step(log, log_entry)

        # Create a logging continuation that captures the result
        logging_cont = fn result ->
          result_timestamp = :os.system_time(:microsecond)

          # Update the log entry with the result
          result_entry = %LogEntry{
            step_id: updated_log.current_step,
            timestamp: result_timestamp,
            effect: eff,
            input: u,
            output: result,
            step_type: :continuation,
            continuation_id: "cont_#{log.current_step}",
            parent_step_id: log.current_step
          }

          result_log = ComputationLog.add_step(updated_log, result_entry)

          Logger.info("Logged effect: #{eff}, input: #{inspect(u)}, result: #{inspect(result)}")

          # Continue with the original computation
          q_apply(q, result)
          |> handle_with_log(result_log, ret)
        end

        # Return the impure computation with our logging continuation
        %Freer.Impure{eff: eff, mval: u, q: [logging_cont]}
    end
  end

  @spec try_resume_from_log(ComputationLog.t(), atom, any) ::
          {:resume, any, ComputationLog.t()} | :continue
  defp try_resume_from_log(log, eff, input) do
    # Look for a matching step in the log
    matching_step =
      log.steps
      # Process in chronological order
      |> Enum.reverse()
      |> Enum.find(fn step ->
        step.effect == eff and step.input == input and step.step_type == :effect
      end)

    case matching_step do
      nil ->
        :continue

      step ->
        # Find the corresponding continuation result
        result_step =
          Enum.find(log.steps, fn s ->
            s.parent_step_id == step.step_id and s.step_type == :continuation
          end)

        case result_step do
          nil -> :continue
          result -> {:resume, result.output, log}
        end
    end
  end

  @doc """
  Resume a computation from a persisted log.
  This allows continuing computation from where it left off.
  """
  @spec resume_computation(freer, ComputationLog.t()) :: freer
  def resume_computation(computation, log) do
    case log.status do
      :completed ->
        # Computation already completed, return the result
        Freer.return({log.result, log})

      :error ->
        # Computation previously errored, could re-raise or handle differently
        raise "Cannot resume errored computation: #{inspect(log.error)}"

      :yielded ->
        # Resume from yield point
        Logger.info("Resuming yielded computation from step #{log.current_step}")

        handle_with_log(computation, log, fn log ->
          fn result -> Freer.return({result, log}) end
        end)

      :running ->
        # Resume normal computation
        Logger.info("Resuming computation from step #{log.current_step}")

        handle_with_log(computation, log, fn log ->
          fn result -> Freer.return({result, log}) end
        end)
    end
  end

  @doc """
  Create a yield effect that can be resumed later.
  """
  @spec yield_computation(any) :: freer
  def yield_computation(yield_value) do
    send_effect({:yield, yield_value}, :yield)
  end

  @doc """
  Handle yield effects by updating the log status.
  """
  @spec handle_yield(freer, ComputationLog.t()) :: freer
  def handle_yield(computation, log \\ ComputationLog.new()) do
    handle_relay(
      computation,
      [:yield],
      fn result -> Freer.return({result, log}) end,
      fn {:yield, value}, k ->
        yielded_log = ComputationLog.yield(log, %{yield_value: value, continuation: k})
        Logger.info("Computation yielded with value: #{inspect(value)}")
        Freer.return({:yielded, yielded_log})
      end
    )
  end
end

# Example usage of handle_all_s:
#
# require Freer
# computation =
#   Freer.con [Numbers, Reader.Ops] do
#     steps a <- number(10),
#           b <- get(),
#           c <- add(a, b) do
#       multiply(a, c)
#     end
#   end
#
# result =
#   computation
#   |> Freer.handle_all_s({debug: true, step: 0})  # Logs all steps with state
#   |> run_numbers()                               # Interpret Numbers effects
#   |> run_reader(5)                              # Provide reader environment
#   |> Freer.run()
#
# # Result: {:number, {150, {debug: true, step: 0}}}
# # Logs show all intermediate steps with state information

# Example usage of structured logging:
#
# # Basic logging
# computation =
#   Freer.con [Numbers] do
#     steps a <- number(42),
#           b <- number(8) do
#       add(a, b)
#     end
#   end
#
# {result, log} =
#   computation
#   |> Freer.handle_with_log()
#   |> run_numbers()
#   |> Freer.run()
#
# # Persist log for later resumption
# {:ok, json_log} = ComputationLog.persist(log)
# File.write!("computation.json", json_log)
#
# # Resume from persisted log
# {:ok, loaded_log} = File.read!("computation.json") |> ComputationLog.load()
# resumed_result =
#   computation
#   |> Freer.resume_computation(loaded_log)
#   |> run_numbers()
#   |> Freer.run()
#
# # Handle yielding computations
# yielding_computation =
#   Freer.con [Numbers] do
#     steps a <- number(10),
#           _ <- yield_computation("checkpoint_1"),
#           b <- number(20) do
#       add(a, b)
#     end
#   end
#
# {status, yield_log} =
#   yielding_computation
#   |> Freer.handle_yield()
#   |> run_numbers()
#   |> Freer.run()
#
# # status will be :yielded, can resume later
# case status do
#   :yielded ->
#     # Save yield_log and resume later
#     resumed = Freer.resume_computation(yielding_computation, yield_log)
#   result ->
#     # Computation completed normally
#     result
# end

# TODO
# - some scoped effects
#   - error
#   - JSON serialisation of steps
#     - each continuation in a queue is a step
#     - we can capture inputs and outputs
#   - syntax for scoped effects ?
# - a testing approach
#   - helpers for creating test handlers
#   - and fuzzing/property-based-testing help
# - can we construct a log/resume handler ?
#   - a handler which records a de/seriializable statement/result log,
#     and if there's already a log, and the statements match then
#     short-circuits and returns the result directly
#   - imposes the constraint that statements/results must be de/serializable
#   - when "resuming", we must follow the continuation chain sufficienly well
#     that the binds that need to happen (for expressions which aren't
#     completely short-circuited) happen correctly
