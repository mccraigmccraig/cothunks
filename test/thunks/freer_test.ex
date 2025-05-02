defmodule Thunks.FreerTest do
  use ExUnit.Case

  alias Thunks.Freer

  describe "pure" do
    test "it wraps a value" do
      assert {:pure, 10} === Freer.pure(10)
    end
  end

  describe "etaf" do
    test "it wraps values into the Freer Monad" do
      assert {:impure, :val, &Freer.pure/1} === Freer.etaf(:val)
    end
  end

  describe "return" do
    test "it returns a value" do
      assert {:pure, 10} === Freer.return(10)
    end
  end

  describe "bind" do
    test "it binds a value" do
      assert {:impure, 10, f} =
               Freer.etaf(10)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)

      assert {:pure, 200} == f.(100)
    end

    test "it binds repeatedly with pure expressions" do
      assert {:impure, 10, f} =
               Freer.etaf(10)
               |> Freer.bind(fn x -> Freer.return(2 * x) end)
               |> Freer.bind(fn x -> Freer.return(5 + x) end)

      assert {:pure, 205} = f.(100)
    end

    test "it binds repeatedly with impoure expressions" do
      assert {:impure, 10, f} =
               Freer.etaf(10)
               |> Freer.bind(fn x ->
                 x |> Freer.etaf() |> Freer.bind(fn y -> Freer.return(2 * y) end)
               end)
               |> Freer.bind(fn x ->
                 x |> Freer.etaf() |> Freer.bind(fn y -> Freer.return(5 + y) end)
               end)

      # each invocation of the composed function returns
      # the next step, so we thread the values through
      # repeated invocations
      assert {:impure, 100, g} = f.(100)
      assert {:impure, 200, h} = g.(100)
      assert {:pure, 205} = h.(200)
    end
  end

  describe "gtgtgt" do
    test "it composes monadic functions on a pure value" do
      f =
        Freer.gtgtgt(
          fn x -> Freer.return(2 * x) end,
          fn x -> Freer.return(5 + x) end
        )

      # functions on pure values get evaluated immediately
      assert {:pure, 5} = f.(0)
      assert {:pure, 25} = f.(10)
    end

    test "it composes monadic functions on an impure value" do
      f =
        Freer.gtgtgt(
          fn x -> Freer.etaf(2 * x) end,
          fn x -> Freer.return(5 + x) end
        )

      # each invocation of the composed function returns
      # the next step
      assert {:impure, 0, g1} = f.(0)
      assert {:pure, 5} = g1.(0)

      assert {:impure, 20, g2} = f.(10)
      assert {:pure, 25} = g2.(20)
    end
  end

  defmodule Thunks.FreerTest.Numbers do
    # define constructors for a simple language with
    # - number
    # - error
    # - multiply operation
    # - divide operation

    def number(a), do: Freer.etaf({:number, a})
    def error(e), do: Freer.etaf({:error, e})
    def add(a, b), do: Freer.etaf({:add, a, b})
    def subtract(a, b), do: Freer.etaf({:subtract, a, b})
    def multiply(a, b), do: Freer.etaf({:multiply, a, b})
    def divide(a, b), do: Freer.etaf({:divide, a, b})

    # interpret the langauge with unit + bind functions

    def unit(n), do: {:number, n}

    def bind({:number, n}, f), do: f.(n)
    def bind({:error, err}, _f), do: {:error, err}
    def bind({:add, a, b}, f), do: f.(a + b)
    def bind({:subtract, a, b}, f), do: f.(a - b)
    def bind({:multiply, a, b}, f), do: f.(a * b)

    def bind({:divide, a, b}, f) do
      if b != 0 do
        f.(a / b)
      else
        {:error, "divide by zero: #{a}/#{b}"}
      end
    end
  end

  alias Thunks.FreerTest.Numbers

  # now take the interpreter for a run

  describe "interpret" do
    test "it interprets a pure value" do
    end

    test "it interprets a short sequence of operations" do
      v =
        Numbers.number(10)
        |> Freer.bind(fn x -> Numbers.multiply(x, 10) end)

      o = Freer.interpret(v, &Numbers.unit/1, &Numbers.bind/2)

      assert {:number, 100} = o
    end

    test "it interprets a slightly longer sequence of operations" do
      v =
        Numbers.number(10)
        |> Freer.bind(fn a -> Numbers.multiply(a, 5) end)
        |> Freer.bind(fn b -> Numbers.add(b, 30) end)
        |> Freer.bind(fn c -> Numbers.divide(c, 20) end)
        |> Freer.bind(fn d -> Numbers.subtract(d, 8) end)

      o = Freer.interpret(v, &Numbers.unit/1, &Numbers.bind/2)

      assert {:number, -4.0} = o
    end

    test "it interprets nested operations" do
      v =
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

      o = Freer.interpret(v, &Numbers.unit/1, &Numbers.bind/2)

      assert {:number, 205} = o
    end

    test "it short circuits on divide by zero" do
      v =
        Numbers.number(10)
        |> Freer.bind(fn x -> Numbers.multiply(x, 10) end)
        |> Freer.bind(fn y -> Numbers.divide(y, 0) end)

      o = Freer.interpret(v, &Numbers.unit/1, &Numbers.bind/2)

      assert {:error, err} = o
      assert err =~ ~r/divide by zero/
    end
  end

  describe "interpreter" do
    test "it builds an interpreter" do
      v =
        Numbers.number(10)
        |> Freer.bind(fn a -> Numbers.multiply(a, 5) end)
        |> Freer.bind(fn b -> Numbers.add(b, 30) end)
        |> Freer.bind(fn c -> Numbers.divide(c, 20) end)
        |> Freer.bind(fn d -> Numbers.subtract(d, 8) end)

      interpreter = Freer.interpreter(&Numbers.unit/1, &Numbers.bind/2)

      o = interpreter.(v)

      assert {:number, -4.0} = o
    end
  end
end
