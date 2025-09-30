defmodule Freya.Effects.ErrorTest do
  use ExUnit.Case

  import Freya.Con

  alias Freya.Freer
  alias Freya.Effects.Error
  alias Freya.Effects.ErrorHandler
  alias Freya.Effects.Writer
  alias Freya.Effects.WriterHandler
  alias Freya.Run
  alias Freya.RunOutcome
  alias Freya.ErrorResult

  describe "throw/catch basics" do
    test "throw without catch propagates error" do
      fv =
        con [Error] do
          _ <- throw_fx(:oops)
          return(:unreachable)
        end

      runner =
        Run.with_handlers(e: Error.Handler)

      outcome = Run.run(fv, runner)

      assert %RunOutcome{result: %ErrorResult{error: :oops}} = outcome
    end
  end

  describe "recovery" do
    test "catch recovers from throw" do
      fv =
        con Error do
          res <-
            catch_fx(
              con Error do
                _ <- throw_fx(:bad)
                return(:nope)
              end,
              fn err -> return({:recovered, err}) end
            )

          return(res)
        end

      runner =
        Run.with_handlers(e: Error.Handler)

      outcome = Run.run(fv, runner)

      assert %Freya.RunOutcome{
               result: %Freya.OkResult{value: {:recovered, :bad}}
             } = outcome
    end
  end

  #   test "catch passes through success" do
  #     require Freer
  #     require Freya.Con

  #     fv =
  #       Freya.Con.con Error do
  #         res <- Error.catch_fx(Freer.return(42), fn _ -> Freer.return(0) end)
  #         Freer.return(res)
  #       end

  #     %Freya.RunOutcome{result: res, outputs: _out} =
  #       fv |> ErrorHandler.interpret_error() |> Freer.run()

  #     assert Freya.Protocols.Result.type(res) == Freya.OkResult
  #     assert Freya.Protocols.Result.value(res) == 42
  #   end
  # end

  # describe "composition with Writer and State" do
  #   test "writer before throw is kept; after is skipped" do
  #     require Freer
  #     require Freya.Con

  #     fv =
  #       Freya.Con.con [Error, Writer] do
  #         _ <- Writer.put(:before)
  #         _ <- Error.throw_fx(:bad)
  #         _ <- Writer.put(:after)
  #         Freer.return(:unreachable)
  #       end

  #     %Freya.RunOutcome{result: res, outputs: out} =
  #       fv |> ErrorHandler.interpret_error() |> WriterHandler.interpret_writer() |> Freer.run()

  #     assert out.writer == [:before]
  #     assert Freya.Protocols.Result.type(res) == Freya.ErrorResult
  #     assert Freya.Protocols.Result.value(res) == :bad
  #   end

  #   test "nested catch with state" do
  #     require Freer
  #     require Freya.Con

  #     fv =
  #       Freya.Con.con [Error, Writer] do
  #         # emulate state with Reader+Writer interpreter
  #         res <-
  #           Error.catch_fx(
  #             Freya.Con.con [Error, Writer] do
  #               _ <- Error.throw_fx(:inner)
  #               _ <- Writer.put(:after_throw)
  #               Freer.return(:nope)
  #             end,
  #             fn err ->
  #               Freya.Con.con [Writer] do
  #                 _ <- Writer.put({:handled, err})
  #                 Freer.return(:ok)
  #               end
  #             end
  #           )

  #         Freer.return(res)
  #       end

  #     %Freya.RunOutcome{result: res, outputs: out} =
  #       fv
  #       |> ErrorHandler.interpret_error()
  #       |> WriterHandler.interpret_writer()
  #       |> Freer.run()

  #     assert Freya.Protocols.Result.type(res) == Freya.OkResult
  #     assert Freya.Protocols.Result.value(res) == :ok
  #     assert out[:writer] == [{:handled, :inner}]
  #   end
  # end
end
