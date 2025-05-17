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
      assert %Impure{eff: Thunks.FreerTest, mval: :val, q: [&Freer.pure/1]} ==
               Freer.etaf(:val, Thunks.FreerTest)
    end
  end

  describe "return" do
    test "it returns a value" do
      assert %Pure{val: 10} === Freer.return(10)
    end
  end

  # describe "bind" do
  #   test "it binds a value" do
  #     assert {:impure, 10, f} =
  #              Freer.etaf(10)
  #              |> Freer.bind(fn x -> Freer.return(2 * x) end)

  #     assert {:pure, 200} == f.(100)
  #   end

  #   test "it binds repeatedly with pure expressions" do
  #     assert {:impure, 10, f} =
  #              Freer.etaf(10)
  #              |> Freer.bind(fn x -> Freer.return(2 * x) end)
  #              |> Freer.bind(fn x -> Freer.return(5 + x) end)

  #     assert {:pure, 205} = f.(100)
  #   end

  #   test "it binds repeatedly with impoure expressions" do
  #     assert {:impure, 10, f} =
  #              Freer.etaf(10)
  #              |> Freer.bind(fn x ->
  #                x |> Freer.etaf() |> Freer.bind(fn y -> Freer.return(2 * y) end)
  #              end)
  #              |> Freer.bind(fn x ->
  #                x |> Freer.etaf() |> Freer.bind(fn y -> Freer.return(5 + y) end)
  #              end)

  #     # each invocation of the composed function returns
  #     # the next step, so we thread the values through
  #     # repeated invocations
  #     assert {:impure, 100, g} = f.(100)
  #     assert {:impure, 200, h} = g.(100)
  #     assert {:pure, 205} = h.(200)
  #   end
  # end

  # describe "gtgtgt" do
  #   test "it composes monadic functions on a pure value" do
  #     f =
  #       Freer.gtgtgt(
  #         fn x -> Freer.return(2 * x) end,
  #         fn x -> Freer.return(5 + x) end
  #       )

  #     # functions on pure values get evaluated immediately
  #     assert {:pure, 5} = f.(0)
  #     assert {:pure, 25} = f.(10)
  #   end

  #   test "it composes monadic functions on an impure value" do
  #     f =
  #       Freer.gtgtgt(
  #         fn x -> Freer.etaf(2 * x) end,
  #         fn x -> Freer.return(5 + x) end
  #       )

  #     # each invocation of the composed function returns
  #     # the next step
  #     assert {:impure, 0, g1} = f.(0)
  #     assert {:pure, 5} = g1.(0)

  #     assert {:impure, 20, g2} = f.(10)
  #     assert {:pure, 25} = g2.(20)
  #   end
  # end

  # # define constructors for a simple language with
  # # - number
  # # - error
  # # - add operation
  # # - subtract ooperation
  # # - multiply operation
  # # - divide operation
  # defmodule Numbers do
  #   def number(a), do: {:number, a}
  #   def error(e), do: {:error, e}
  #   def add(a, b), do: {:add, a, b}
  #   def subtract(a, b), do: {:subtract, a, b}
  #   def multiply(a, b), do: {:multiply, a, b}
  #   def divide(a, b), do: {:divide, a, b}
  # end

  # defmodule AlsoNumbers do
  #   def also_number(a), do: {:also_number, a}
  # end

  # defmodule FreerNumbers do
  #   use FreerOps, ops: Numbers
  # end

  # defmodule FreerAlsoNumbers do
  #   use FreerOps, ops: AlsoNumbers
  # end

  # # interpret the langauge with unit + bind functions
  # defmodule InterpretNumbers do
  #   def unit(n), do: {:number, n}

  #   def bind({:number, n}, f), do: f.(n)
  #   def bind({:also_number, n}, f), do: f.(n)
  #   def bind({:error, err}, _f), do: {:error, err}
  #   def bind({:add, a, b}, f), do: f.(a + b)
  #   def bind({:subtract, a, b}, f), do: f.(a - b)
  #   def bind({:multiply, a, b}, f), do: f.(a * b)

  #   def bind({:divide, a, b}, f) do
  #     if b != 0 do
  #       f.(a / b)
  #     else
  #       {:error, "divide by zero: #{a}/#{b}"}
  #     end
  #   end
  # end

  # # now take the interpreter for a run

  # describe "interpret" do
  #   test "it interprets a pure value" do
  #   end

  #   test "it interprets a short sequence of operations" do
  #     v =
  #       FreerNumbers.number(10)
  #       |> Freer.bind(fn x -> FreerNumbers.multiply(x, 10) end)

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:number, 100} = o
  #   end

  #   test "it interprets a slightly longer sequence of operations" do
  #     v =
  #       FreerNumbers.number(10)
  #       |> Freer.bind(fn a -> FreerNumbers.multiply(a, 5) end)
  #       |> Freer.bind(fn b -> FreerNumbers.add(b, 30) end)
  #       |> Freer.bind(fn c -> FreerNumbers.divide(c, 20) end)
  #       |> Freer.bind(fn d -> FreerNumbers.subtract(d, 8) end)

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:number, -4.0} = o
  #   end

  #   test "it interprets nested operations" do
  #     v =
  #       FreerNumbers.number(10)
  #       |> Freer.bind(fn a ->
  #         FreerNumbers.number(20)
  #         |> Freer.bind(fn b ->
  #           FreerNumbers.number(5)
  #           |> Freer.bind(fn c ->
  #             FreerNumbers.multiply(a, b)
  #             |> Freer.bind(fn d ->
  #               FreerNumbers.add(c, d)
  #             end)
  #           end)
  #         end)
  #       end)

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:number, 205} = o
  #   end

  #   test "it short circuits on divide by zero" do
  #     v =
  #       FreerNumbers.number(10)
  #       |> Freer.bind(fn x -> FreerNumbers.multiply(x, 10) end)
  #       |> Freer.bind(fn y -> FreerNumbers.divide(y, 0) end)
  #       |> Freer.bind(fn z -> FreerNumbers.add(z, 10) end)

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:error, err} = o
  #     assert err =~ ~r/divide by zero/
  #   end
  # end

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

  # describe "con" do
  #   test "it provides a nice bind syntax sugar" do
  #     require Freer

  #     v =
  #       Freer.con FreerNumbers do
  #         steps a <- number(10),
  #               b <- number(1000),
  #               c <- add(a, b),
  #               d <- multiply(a, b) do
  #           subtract(d, c)
  #         end
  #       end

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:number, 8990} == o
  #   end

  #   test "it can mix multiple ops modules" do
  #     require Freer

  #     v =
  #       Freer.con [FreerNumbers, FreerAlsoNumbers] do
  #         steps a <- number(10),
  #               b <- also_number(1000),
  #               c <- add(a, b),
  #               d <- multiply(a, b) do
  #           subtract(d, c)
  #         end
  #       end

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:number, 8990} == o
  #   end

  #   test "it short circuits" do
  #     require Freer

  #     v =
  #       Freer.con FreerNumbers do
  #         steps a <- number(10),
  #               b <- number(1000),
  #               c <- divide(a, 0) do
  #           multiply(b, c)
  #         end
  #       end

  #     o = Freer.interpret(v, &InterpretNumbers.unit/1, &InterpretNumbers.bind/2)

  #     assert {:error, err} = o
  #     assert err =~ ~r/divide by zero/
  #   end
  # end
end
