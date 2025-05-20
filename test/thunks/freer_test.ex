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

  describe "etaf" do
    test "it wraps values into the Freer Monad" do
      assert %Impure{eff: EffectMod, mval: :val, q: [&Freer.pure/1]} ==
               Freer.etaf(:val, EffectMod)
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
               Freer.etaf(10, EffectMod)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)

      assert %Pure{val: 10} == pure_f.(10)
      assert %Pure{val: 20} == step_f.(10)
    end

    test "it binds repeatedly with pure expressions" do
      assert %Impure{eff: EffectMod, mval: 10, q: [pure_f, step_1_f, step_2_f]} =
               Freer.etaf(10, EffectMod)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)
               |> Freer.bind(fn x -> Freer.return(5 + x) end)

      assert %Pure{val: 10} = pure_f.(10)
      assert %Pure{val: 20} = step_1_f.(10)
      assert %Pure{val: 25} = step_2_f.(20)
    end

    test "it binds repeatedly with impure expressions" do
      assert %Impure{eff: EffectMod, mval: 10, q: [step_1, step_2, step_3]} =
               Freer.etaf(10, EffectMod)
               |> Freer.bind(fn x ->
                 x |> Freer.etaf(EffectMod) |> Freer.bind(fn y -> Freer.return(2 * y) end)
               end)
               |> Freer.bind(fn x ->
                 x |> Freer.etaf(EffectMod) |> Freer.bind(fn y -> Freer.return(5 + y) end)
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
  defmodule Numbers do
    def number(a), do: {:number, a}
    def error(e), do: {:error, e}
    def add(a, b), do: {:add, a, b}
    def subtract(a, b), do: {:subtract, a, b}
    def multiply(a, b), do: {:multiply, a, b}
    def divide(a, b), do: {:divide, a, b}
  end

  defmodule FreerNumbers do
    use FreerOps, ops: Numbers
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

  defmodule Reader do
    def get(), do: :get
  end

  defmodule FreerReader do
    use FreerOps, ops: Reader
  end

  def run_reader(fv, reader_val) do
    fv
    |> Freer.handle_relay(
      [Reader],
      &Freer.return/1,
      fn :get, k -> k.(reader_val) end
    )
  end

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
        FreerNumbers.number(10)
        |> Freer.bind(fn x -> FreerNumbers.multiply(x, 10) end)

      result = fv |> run_numbers() |> Freer.run()

      # o = Freer.run(handled)
      assert {:number, 100} = result
    end

    test "it interprets a more complex composition of operations" do
      fv =
        FreerNumbers.number(10)
        |> Freer.bind(fn x ->
          FreerNumbers.number(2) |> Freer.bind(fn y -> Freer.return(x + y) end)
        end)
        |> Freer.bind(fn x ->
          FreerNumbers.number(5) |> Freer.bind(fn z -> Freer.return(x * z) end)
        end)

      result = fv |> run_numbers() |> Freer.run()

      assert {:number, 60} = result
    end

    # test "it interprets a slightly longer sequence of operations" do
    #   v =
    #     FreerNumbers.number(10)
    #     |> Freer.bind(fn a -> FreerNumbers.multiply(a, 5) end)
    #     |> Freer.bind(fn b -> FreerNumbers.add(b, 30) end)
    #     |> Freer.bind(fn c -> FreerNumbers.divide(c, 20) end)
    #     |> Freer.bind(fn d -> FreerNumbers.subtract(d, 8) end)

    #   o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

    #   assert {:number, -4.0} = o
    # end

    # test "it interprets nested operations" do
    #   v =
    #     FreerNumbers.number(10)
    #     |> Freer.bind(fn a ->
    #       FreerNumbers.number(20)
    #       |> Freer.bind(fn b ->
    #         FreerNumbers.number(5)
    #         |> Freer.bind(fn c ->
    #           FreerNumbers.multiply(a, b)
    #           |> Freer.bind(fn d ->
    #             FreerNumbers.add(c, d)
    #           end)
    #         end)
    #       end)
    #     end)

    #   o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

    #   assert {:number, 205} = o
    # end

    # test "it short circuits on divide by zero" do
    #   v =
    #     FreerNumbers.number(10)
    #     |> Freer.bind(fn x -> FreerNumbers.multiply(x, 10) end)
    #     |> Freer.bind(fn y -> FreerNumbers.divide(y, 0) end)
    #     |> Freer.bind(fn z -> FreerNumbers.add(z, 10) end)

    #   o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

    #   assert {:error, err} = o
    #   assert err =~ ~r/divide by zero/
    # end
  end

  # describe "interpreter" do
  #   test "it builds an interpreter" do
  #     v =
  #       FreerNumbers.number(10)
  #       |> Freer.bind(fn a -> FreerNumbers.multiply(a, 5) end)
  #       |> Freer.bind(fn b -> FreerNumbers.add(b, 30) end)
  #       |> Freer.bind(fn c -> FreerNumbers.divide(c, 20) end)
  #       |> Freer.bind(fn d -> FreerNumbers.subtract(d, 8) end)

  #     interpreter = Freer.interpreter(&InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     o = interpreter.(v)

  #     assert {:number, -4.0} = o
  #   end
  # end

  describe "con" do
    test "it provides a nice bind syntax sugar" do
      require Freer

      fv =
        Freer.con FreerNumbers do
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

    test "it can mix multiple ops modules" do
      require Freer

      fv =
        Freer.con [FreerNumbers, FreerReader] do
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

    test "it short circuits" do
      require Freer

      fv =
        Freer.con FreerNumbers do
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
  end
end
