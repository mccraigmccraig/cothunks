defmodule Thunks.FreerTest do
  use ExUnit.Case

  require Logger
  alias Thunks.Freer
  alias Thunks.Freer.{Pure, Impure}
  alias Thunks.FreerOps

  describe "pure" do
    test "it wraps a value" do
      assert %Pure{val: 10} === Freer.pure(10)
    end
  end

  describe "send" do
    test "it wraps values into the Freer Monad" do
      assert %Impure{eff: EffectMod, mval: :val, q: [&Freer.pure/1]} ==
               Freer.send(:val, EffectMod)
    end
  end

  describe "return" do
    test "it returns a value" do
      assert %Pure{val: 10} === Freer.return(10)
    end
  end

  describe "bind" do
    test "it binds a value" do
      assert %Impure{eff: EffectMod, mval: 10, q: [pure_f, step_f]} =
               Freer.send(10, EffectMod)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)

      assert %Pure{val: 10} == pure_f.(10)
      assert %Pure{val: 20} == step_f.(10)
    end

    test "it binds repeatedly with pure expressions" do
      assert %Impure{eff: EffectMod, mval: 10, q: [pure_f, step_1_f, step_2_f]} =
               Freer.send(10, EffectMod)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)
               |> Freer.bind(fn x -> Freer.return(5 + x) end)

      assert %Pure{val: 10} = pure_f.(10)
      assert %Pure{val: 20} = step_1_f.(10)
      assert %Pure{val: 25} = step_2_f.(20)
    end

    test "it binds repeatedly with impure expressions" do
      assert %Impure{eff: EffectMod, mval: 10, q: [step_1, step_2, step_3]} =
               Freer.send(10, EffectMod)
               |> Freer.bind(fn x ->
                 x |> Freer.send(EffectMod) |> Freer.bind(fn y -> Freer.return(2 * y) end)
               end)
               |> Freer.bind(fn x ->
                 x |> Freer.send(EffectMod) |> Freer.bind(fn y -> Freer.return(5 + y) end)
               end)

      # trace the steps manually, feeding values from one into the next - this
      # is exactly what an interpreter for the identity effect would do
      pure = &Freer.pure/1
      assert %Pure{val: 10} = step_1.(10)
      assert %Impure{eff: EffectMod, mval: 10, q: [^pure, step_2_2]} = step_2.(10)
      assert %Pure{val: 20} = step_2_2.(10)
      assert %Impure{eff: EffectMod, mval: 20, q: [^pure, step_3_2]} = step_3.(20)
      assert %Pure{val: 25} = step_3_2.(20)
    end
  end

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
    use FreerOps, ops: NumbersGrammar
  end

  # interpret the Numbers langauge with ret + handle functions
  #
  # ret and handle must return Freer structs
  #
  # - ret : wrap a plain value in a Freer<Numbers>
  # - handle : interpret a Numbers statement, either
  #  passing a plain value on to the continuation, or
  #  short-circuit returning a Freer<Numbers> 
  defmodule InterpretNumbers do
    # wrap a value in a Numbers structure
    def ret(n), do: Freer.return({:number, n})

    # interpret a Numbers structure and pass a value on to
    # the continuation. The continuiation will return a Freer,
    # so handle must return a Freer too if it doesn't call
    # the continuation
    def handle({:number, n}, k), do: k.(n)
    def handle({:also_number, n}, k), do: k.(n)
    def handle({:add, a, b}, k), do: k.(a + b)
    def handle({:subtract, a, b}, k), do: k.(a - b)
    def handle({:multiply, a, b}, k), do: k.(a * b)

    def handle({:divide, a, b}, k) do
      if b != 0 do
        k.(a / b)
      else
        Freer.return({:error, "divide by zero: #{a}/#{b}"})
      end
    end

    def handle({:error, err}, _f), do: Freer.return({:error, err})
  end

  def run_numbers(fv) do
    fv
    |> Freer.handle_relay(
      [Numbers],
      &InterpretNumbers.ret/1,
      &InterpretNumbers.handle/2
    )
  end

  # Reader and Writer effects have been moved to their own modules
  # Thunks.Reader and Thunks.Writer

  def run_reader(fv, reader_val) do
    Thunks.Reader.run(fv, reader_val)
  end

  def run_writer(fv) do
    Thunks.Writer.run(fv)
  end

  # State effect has been moved to its own module Thunks.State

  describe "q_apply" do
  end

  describe "q_comp" do
  end

  # now take the interpreter for a run

  describe "interpret" do
    test "it interprets a pure value" do
      fv = Freer.pure(10)

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, 10} = result
    end

    test "it interprets a short sequence of operations" do
      fv =
        Numbers.number(10)
        |> Freer.bind(fn x -> Numbers.multiply(x, 10) end)

      result = fv |> run_numbers() |> Freer.run()

      # o = Freer.run(handled)
      assert {:number, 100} = result
    end

    test "it interprets a more complex composition of operations" do
      fv =
        Numbers.number(10)
        |> Freer.bind(fn x ->
          Numbers.number(2) |> Freer.bind(fn y -> Freer.return(x + y) end)
        end)
        |> Freer.bind(fn x ->
          Numbers.number(5) |> Freer.bind(fn z -> Freer.return(x * z) end)
        end)

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, 60} = result
    end

    test "it interprets a slightly longer sequence of operations" do
      fv =
        Numbers.number(10)
        |> Freer.bind(fn a -> Numbers.multiply(a, 5) end)
        |> Freer.bind(fn b -> Numbers.add(b, 30) end)
        |> Freer.bind(fn c -> Numbers.divide(c, 20) end)
        |> Freer.bind(fn d -> Numbers.subtract(d, 8) end)

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, -4.0} = result
    end

    test "it interprets nested operations" do
      fv =
        Numbers.number(10)
        |> Freer.bind(fn a ->
          Numbers.number(20)
          |> Freer.bind(fn b ->
            Numbers.number(5)
            |> Freer.bind(fn c ->
              Numbers.multiply(a, b)
              |> Freer.bind(fn d ->
                Numbers.add(c, d)
              end)
            end)
          end)
        end)

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, 205} = result
    end

    test "it short circuits on divide by zero" do
      fv =
        Numbers.number(10)
        |> Freer.bind(fn x -> Numbers.multiply(x, 10) end)
        |> Freer.bind(fn y -> Numbers.divide(y, 0) end)
        |> Freer.bind(fn z -> Numbers.add(z, 10) end)

      result = fv |> run_numbers() |> Freer.run()

      assert {:error, err} = result
      assert err =~ ~r/divide by zero/
    end
  end

  describe "con" do
    test "it provides a nice bind syntax sugar" do
      require Freer

      fv =
        Freer.con Numbers do
          steps a <- number(10),
                b <- number(1000),
                c <- add(a, b),
                d <- multiply(a, b) do
            subtract(d, c)
          end
        end

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, 8990} == result
    end

    test "it can run a reader" do
      require Freer

      fv =
        Freer.con Thunks.Reader.Ops do
          steps a <- Freer.return(10),
                b <- get() do
            Freer.return(a + b)
          end
        end

      result = fv |> run_reader(12) |> Freer.run()

      assert 22 = result
    end

    test "it can run a reader and a writer" do
      require Freer

      fv =
        Freer.con [Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps a <- Freer.return(10),
                b <- get(),
                _c <- put(a + b),
                _d <- put(a * b) do
            Freer.return(2 * (a + b))
          end
        end

      result = fv |> run_writer() |> run_reader(12) |> Freer.run()

      # q: why is the order of the writer monoid reversed from what I expected ?
      # a: because the handler calls the continuation and prepends the put value
      # the continuation's output, so order is preserved
      assert {44, [22, 120]} = result

      # the order of the handlers should not matter for this combination of effects
      result2 = fv |> run_reader(12) |> run_writer() |> Freer.run()
      assert result2 == result
    end

    test "it can mix numbers with a reader" do
      require Freer

      fv =
        Freer.con [Numbers, Thunks.Reader.Ops] do
          steps a <- number(10),
                b <- get(),
                c <- add(a, b),
                d <- multiply(a, b) do
            subtract(d, c)
          end
        end

      result = fv |> run_numbers() |> run_reader(12) |> Freer.run()

      # handler order should not matter for these effects
      result2 = fv |> run_reader(12) |> run_numbers() |> Freer.run()

      assert {:number, 98} == result
      assert result == result2
    end

    test "it can mix numbers with a reader and a writer" do
      require Freer

      fv =
        Freer.con [Numbers, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps a <- number(10),
                put(a),
                b <- get(),
                put(b),
                c <- add(a, b),
                put(c),
                d <- multiply(a, b) do
            # you can use the grammar constructs inside the do block, but
            # you have to sequence them manually
            put(d)
            |> Freer.bind(fn _ ->
              subtract(d, c)
            end)
          end
        end

      result =
        fv |> run_numbers() |> run_reader(12) |> run_writer() |> Freer.run()

      assert {{:number, 98}, [10, 12, 22, 120]} == result

      # handler order does matter with a Writer effect
      result2 = fv |> run_writer |> run_reader(12) |> run_numbers() |> Freer.run()
      assert {:number, {98, [10, 12, 22, 120]}} == result2
    end

    test "it can mix numbers with the state interpretation of Reader+Writer" do
      require Freer

      fv =
        Freer.con [Numbers, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps a <- get(),
                b <- number(10),
                put(a + b),
                c <- multiply(a, b),
                d <- get() do
            subtract(d, c)
          end
        end

      result =
        fv |> run_numbers() |> Thunks.State.run(12) |> Freer.run()

      assert {{:number, -98}, 22} == result
    end

    test "it short circuits" do
      require Freer

      fv =
        Freer.con Numbers do
          steps a <- number(10),
                b <- number(1000),
                c <- divide(a, 0) do
            multiply(b, c)
          end
        end

      result = fv |> run_numbers() |> Freer.run()

      assert {:error, err} = result
      assert err =~ ~r/divide by zero/
    end

    test "it short circuits Numbes in combination with other effects" do
      require Freer

      fv =
        Freer.con [Numbers, Thunks.Reader.Ops, Thunks.Writer.Ops] do
          steps a <- get(),
                b <- number(1000),
                c <- divide(a, 0),
                put(c) do
            multiply(b, c)
          end
        end

      result = fv |> run_numbers() |> Thunks.State.run(10) |> Freer.run()

      assert {{:error, err}, 10} = result
      assert err =~ ~r/divide by zero/
    end
  end
end
