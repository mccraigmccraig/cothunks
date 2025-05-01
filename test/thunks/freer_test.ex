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

  def error(e) do
    Freer.etaf({:error, e})
  end

  def number(a) do
    Freer.etaf({:number, a})
  end

  def multiply(a, b) do
    Freer.etaf({:multiply, a, b})
  end

  def divide(a, b) do
    Freer.etaf({:divide, a, b})
  end

  describe "interpret" do
    test "it interprets a pure value" do
    end

    test "it interprets a sequence of operations" do
      v =
        number(10)
        |> Freer.bind(fn x -> multiply(x, 10) end)

      o =
        Freer.interpret(
          v,
          fn
            n -> {:number, n}
          end,
          fn
            {:number, n}, f ->
              f.(n)

            {:multiply, a, b}, f ->
              f.(a * b)

            {:divide, a, b}, f ->
              if b != 0 do
                f.(a / b)
                {:error, "divide by zero: #{a} / 0"}
              end

            err, f ->
              f.(err)
          end
        )

      assert {:number, 100} = o
    end

    test "it interprets another sequence of operations" do
      v =
        number(10)
        |> Freer.bind(fn x -> multiply(x, 10) end)
        |> Freer.bind(fn y -> divide(y, 0) end)

      o =
        Freer.interpret(
          v,
          fn
            n -> {:number, n}
          end,
          fn
            {:number, n}, f ->
              f.(n)

            {:multiply, a, b}, f ->
              f.(a * b)

            {:divide, a, b}, f ->
              if b != 0 do
                f.(a / b)
              else
                {:error, "divide by zero: #{a} / #{b}"}
              end

            {:error, err}, _f ->
              {:error, err}
          end
        )

      assert {:error, err} = o
      assert err =~ ~r/divide by zero/
    end
  end
end
