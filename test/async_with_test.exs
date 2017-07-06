defmodule AsyncWithTest do
  use ExUnit.Case
  doctest AsyncWith

  test "greets the world" do
    assert AsyncWith.hello() == :world
  end
end
