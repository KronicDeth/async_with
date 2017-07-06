defmodule AsyncWithTest do
  use ExUnit.Case
  doctest AsyncWith

  defmodule OtherThing do
    require AsyncWith

    # def sleep_5(), do: :timer.sleep(5_000)
    def sleep_5(), do: :ok

    def myfunc(a \\ 1) do
      AsyncWith.async with a <- a,
                       a <- a + a do
                        # a <- sleep_5(),
                        # {1, b} <- {3, 456},
                        # {1, c} <- {2, 123},
                        # # c <- b + 2,
                        # d <- IO.puts("d has run") && 9,
                        # e <- b,
                        # a <- 7 do
                        # {c, d, a}
                        # {a,b,c,d,e}
               a
      end
    end
  end

# IO.inspect OtherThing.myfunc

# expr = quote do
  # with a <- sleep_5,
  #      b <- sleep_1,
  #        c <- do_something(a),
  #        d <- do_something(b),
  #        e <- do_something(a, b) do
  #   {c, d}
  # end
#   # with myvar <- 1,
#   #      %{key: val, otherkey: otherval} <- %{key: 123},
#   #      other_thing <- do_thing(myvar) do
#   #   next_thing(other_thing)
#   #   do_thing(myvar)
#   # end
# end

# IO.inspect Thing.thing(expr)

# [a: {b, []}, c: {d, []}, e: {a, [a]}, f: {expr, [a, c]}]

# # Keys are dependent vars.
# %{
#   [] => [{a, b}, {c, d}],
#   [a] => [{e, a}],
#   [a, c] => [{f, expr}]
# }

# async with a <- b,
#            c <- d,
#            e <- a,
#            f <- expr(a, c) do
#       end
# async with a <- sleep_5,
#            b <- sleep_1,
#            c <- do_something(a),
#            d <- do_something(b),
#            e <- do_something(a, b) do
#         {c, d}
#       end

# collector = Task.async fn ->
#   loop = fn(state, fun) ->
    # new_state = receive do
    #   {0, val} -> put_in(state, 0, {:ok, val})
    #   {1, val} -> put_in(state, 1, {:ok, val})
    #   {2, val} -> put_in(state, 2, {:ok, val})
    #   {3, val} -> put_in(state, 3, {:ok, val})
    #   {4, val} -> put_in(state, 4, {:ok, val})
    # end
# => {:=, [line: 1],
# =>  [{:new_state, [line: 1], nil},
# =>   {:receive, [line: 1],
# =>    [[do: [{:->, [line: 2],
# =>        [[{0, {:val, [line: 2], nil}}],
# =>         {:put_in, [line: 2],
# =>          [{:state, [line: 2], nil}, 0, {:ok, {:val, [line: 2], nil}}]}]},
# =>       {:->, [line: 3],
# =>        [[{1, {:val, [line: 3], nil}}],
# =>         {:put_in, [line: 3],
# =>          [{:state, [line: 3], nil}, 1, {:ok, {:val, [line: 3], nil}}]}]},
# =>       {:->, [line: 4],
# =>        [[{2, {:val, [line: 4], nil}}],
# =>         {:put_in, [line: 4],
# =>          [{:state, [line: 4], nil}, 2, {:ok, {:val, [line: 4], nil}}]}]},
# =>       {:->, [line: 5],
# =>        [[{3, {:val, [line: 5], nil}}],
# =>         {:put_in, [line: 5],
# =>          [{:state, [line: 5], nil}, 3, {:ok, {:val, [line: 5], nil}}]}]},
# =>       {:->, [line: 6],
# =>        [[{4, {:val, [line: 6], nil}}],
# =>         {:put_in, [line: 6],
# =>          [{:state, [line: 6], nil}, 4, {:ok, {:val, [line: 6], nil}}]}]}]]]}]}

    # case new_state do
    #   {{:ok, a}, {:ok, b}, {:ok, c}, {:ok, d}, {:ok, e}} -> {a, b, c, d, e}
    #   _ -> fun.(new_state, fun)
    # end
# => {:case, [line: 1],
# =>  [{:new_state, [line: 1], nil},
# =>   [do: [{:->, [line: 2],
# =>      [[{:{}, [line: 2],
# =>         [ok: {:a, [line: 2], nil}, ok: {:b, [line: 2], nil},
# =>          ok: {:c, [line: 2], nil}, ok: {:d, [line: 2], nil},
# =>          ok: {:e, [line: 2], nil}]}],
# =>       {:{}, [line: 2],
# =>        [{:a, [line: 2], nil}, {:b, [line: 2], nil}, {:c, [line: 2], nil},
# =>         {:d, [line: 2], nil}, {:e, [line: 2], nil}]}]},
# =>     {:->, [line: 3],
# =>      [[{:_, [line: 3], nil}],
# =>       {{:., [line: 3], [{:fun, [line: 3], nil}]}, [line: 3],
# =>        [{:new_state, [line: 3], nil}, {:fun, [line: 3], nil}]}]}]]]}
#   end
#   loop.({:nothing, :nothing, :nothing, :nothing, :nothing}, loop)
# end

# task_e = Task.start_link fn ->
#   loop = fn(state, fun) ->
#     new_state = receive do
#       # We explicitly specify the index
#       # because we have our own
#       # mappings in this Task.
#       {0, val} -> put_in(state, 0, {:ok, val})
#       {1, val} -> put_in(state, 1, {:ok, val})
#     end

#     case new_state do
#       {{:ok, a}, {:ok, b}} -> {a, b}
#       _ -> fun.(new_state, fun)
#     end
#   end

#   {a, b} = loop.({:nothing, :nothing}, loop)
#   val = do_something(a, b)
#   send(collector.pid, {4, val})
# end

# task_d = Task.start_link fn ->
#   b = receive do
#     {1, val} -> val
#   end

#   val = do_something(b)
#   send(collector.pid, {3, val})
# end

# task_c = Task.start_link fn ->
#   a = receive do
#     {0, val} -> val
#   end

#   val = do_something(a)
#   send(collector.pid, {2, val})
# end

# task_b = Task.start_link fn ->
#   val = sleep_1
#   send(task_d.pid, {1, val})
#   send(task_e.pid, {1, val})
#   send(collector.pid, {1, val})
# end

# task_a = Task.start_link fn ->
#   val = sleep_5
#   send(task_c.pid, {0, val})
#   send(task_e.pid, {0, val})
#   send(collector.pid, {0, val})
# end

# # The collector will finish when all the other Tasks finish.
# {a, b, c, d, e} = Task.await(collector)
end
