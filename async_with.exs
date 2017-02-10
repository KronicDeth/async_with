defmodule Thing do
  defmacro async(expr, do: block) do
    IO.inspect expr
    thing(expr, block)
  end

  def thing({:with, _, withs}, block) do
    weths = for weth <- withs, do: do_withs(weth)
    weths = Enum.reject(weths, &(&1 == []))

    {weths, _lefts} =
      Enum.map_reduce(weths, [], fn(weth, acc) ->
        {lefts, rights, expr} = weth
        rights = Enum.uniq(rights)
        rights = Enum.filter(rights, &(&1 in acc))
        {{lefts, rights, expr}, lefts ++ acc}
      end)

    {weths, {_, vars}} =
      Enum.map_reduce(weths, {-1, []}, fn(weth, acc) ->
        {lefts, rights, expr} = weth
        {index, current_lefts} = acc
        rights = Enum.map(rights, fn(x) -> {x, Keyword.get(current_lefts, x)} end)
        {lefts, index} = Enum.map_reduce(lefts, index, &({{&1, &2 + 1}, &2 + 1}))
        current_lefts = lefts ++ current_lefts
        {{lefts, rights, expr}, {index, current_lefts}}
      end)
    IO.inspect weths
    col_ast = collector_ast(vars)
    t_ast = tasks_ast(weths)
    IO.inspect col_ast
    IO.inspect t_ast
    quote do
      unquote(col_ast)
      unquote(t_ast)
      # send(collector.pid, {0, 0})
      # send(collector.pid, {1, 1})
      # send(collector.pid, {2, 2})
      # send(collector.pid, {3, 3})
      # send(collector.pid, {4, 4})
      # send(collector.pid, {5, 5})
      with unquote(collector_assignment(vars)) do
        unquote(block)
      end
    end
  end

  defp tasks_ast(weths = [{_lefts, _rights, _expr}|_rest]) do
    IO.inspect weths
    tasks_tuple = 1..(length(weths)) |> Enum.to_list |> List.to_tuple

    asts = for {{lefts, rights, expr}, index} <- Enum.with_index(weths) do
      sends = Enum.map(Enum.with_index(weths),
        fn({{_lefts, rights, _}, index}) ->
          {rights -- (rights -- lefts), index}
        end)
        |> Enum.filter(fn({deps, _index}) -> deps != [] end)
        |> Enum.flat_map(fn({deps, task_index}) ->
          Enum.map(deps, fn({var_name, var_index}) ->
            {var_index, var_name, task_index}
          end)
        end)

      task_ast(index, rights, expr, sends, lefts)
    end

    quote do
      tasks = unquote(Macro.escape tasks_tuple)
      unquote_splicing(asts)
      for task <- Tuple.to_list(tasks) do
        send(task |> elem(1), {:tasks, tasks})
      end
    end
  end

  def task_ast(index, right_vars, clause, sends, left_vars) do
    quote do
      tasks = put_elem(tasks, unquote(index), Task.start fn ->
        tasks = receive do
          {:tasks, tasks} -> tasks
        end

        loop = fn(state, fun) ->
          new_state = unquote(wait_receive(right_vars))
          case new_state do
            unquote(state_match_line(right_vars))
          end
        end

        return = loop.(unquote(Macro.escape expanding_nothing_tuple(right_vars)), loop)

        with unquote_splicing(right_vars_with_clauses(right_vars)),
             unquote(clause) do
          unquote(task_sends(sends))
          unquote(collector_sends(left_vars))
        else
          val ->
            send(collector.pid, {:abort, val})
            Task.start fn ->
              unquote(tasks_send_abort())
            end
        end
      end)
    end
  end

  def right_vars_with_clauses(rights) do
    for {name, index} <- rights do
      quote do
        unquote(Macro.var(name, nil)) = elem(return, unquote(index))
      end
    end
  end

  def wait_receive(vars) do
    case vars do
      [] ->
        quote do
          state
        end
      [_|_] ->
        quote do
          receive(do: unquote(receive_lines(vars)))
        end
    end
  end

  def collector_sends(lefts) do
    Enum.map lefts, fn({var_name, var_index}) ->
      quote do
        send(collector.pid, {unquote(var_index), unquote(Macro.var(var_name, nil))})
      end
    end
  end

  def tasks_send_abort do
    quote do
      Enum.map Tuple.to_list(tasks), fn(task) ->
        elem(task, 1) |> Process.exit(:with_abort)
      end
    end
  end

  def task_sends(sends) do
    Enum.map sends, fn({var_index, var_name, task_index}) ->
      quote do
        IO.inspect tasks
        send(elem(tasks, unquote(task_index)) |> elem(1),
          {unquote(var_index), unquote(Macro.var(var_name, nil))})
      end
    end
  end

  def collector_ast(vars) do
    quote do
      collector = Task.async fn ->
        IO.puts "running"
        loop = fn(state, fun) ->
          new_state = receive(do: unquote(receive_lines(vars)))
          IO.inspect new_state
          case new_state do
            unquote(state_match_line(vars))
          end
        end
        loop.(unquote(Macro.escape nothing_tuple(vars)), loop)
      end
    end
  end

  defp clean_vars(vars, replace \\ nil) do
    IO.puts "clean_vars"
    IO.inspect vars
    vars
    |> Enum.map_reduce([], fn(var = {name, index}, acc) ->
      case name in acc do
        true -> {replace || {:_, index}, acc}
        false -> {var, [name|acc]}
      end
    end)
    |> elem(0)
    |> IO.inspect
  end

  def collector_assignment(vars) do
    nothing = Enum.map(vars, fn _ -> :nothing end)
    cleaned_vars =
      clean_vars(vars)
      |> Enum.reduce(nothing, fn({var, index}, acc) ->
      List.replace_at(acc, index, var)
    end)

    vars_asts = for var <- cleaned_vars, do: Macro.var(var, nil)
    ast = {:{}, [], vars_asts}
    IO.inspect ast
    quote do
      unquote(ast) <- Task.await(collector, 30_000)
    end
  end

  defp nothing_tuple(vars) do
    Enum.map(vars, fn _ -> :nothing end)
    |> List.to_tuple
  end

  defp expanding_nothing_tuple(vars) do
    case vars do
      [] -> {}
      vars ->
        highest =
          Enum.max_by(vars, fn({_, index}) -> index end)
          |> elem(1)

        nothings = 0..highest
        |> Enum.to_list
        |> Enum.map(fn _ -> {:ok, :nothing} end)

        Enum.reduce(vars, nothings, fn({var, index}, acc) ->
          List.replace_at(acc, index, :nothing)
        end)
        |> List.to_tuple
    end
  end

  defp state_match_line(vars) do
    nothing = case vars do
      [] -> []
      vars ->
        highest = Enum.max_by(vars, fn({_, index}) -> index end) |> elem(1)
        Enum.map(0..highest |> Enum.to_list, fn _ -> :nothing end)
    end
    new_vars =
      clean_vars(vars, {:nothing, -1})
    |> Enum.reduce(nothing, fn({var, index}, acc) ->
      case (-1 == index) do
        true -> acc
        false -> List.replace_at(acc, index, var)
      end
    end)

    vars_ast = for var <- new_vars, do: var == :nothing || Macro.var(var, nil)

    cleaned_vars =
      clean_vars(vars)
      |> IO.inspect
      |> Enum.reduce(nothing, fn({var, index}, acc) ->
      List.replace_at(acc, index, var)
    end)
    |> IO.inspect

    oks_vars = for var <- cleaned_vars, do: {:ok, Macro.var(var, nil)}
    IO.inspect oks_vars
    oks = {:{}, [], oks_vars}
    vars_tuple = {:{}, [], vars_ast}

    quote do
      {:abort, return} -> return
      unquote(oks) -> unquote(vars_tuple)
      _ -> fun.(new_state, fun)
    end
  end

  defp receive_lines(vars) do
    clauses = Enum.flat_map(vars, fn({_var, index}) ->
      quote do
        {unquote(index), val} -> put_elem(state, unquote(index), {:ok, val})
      end
    end)

    abort = quote do
      return = {:abort, _return} -> return
    end

    abort ++ clauses
  end

  defp do_withs(expr = {:<-, _, [left, right]}) do
    {do_which_vars(left), do_which_vars(right), expr}
  end
  defp do_withs(otherwise), do: []

  defp do_which_vars(ast) do
    {_, acc} = Macro.prewalk(ast, [], fn x, acc -> {x, which_vars(x) ++ acc} end)
    acc
  end

  defp which_vars({name, meta, context}) when is_atom(context) do
    [name]
  end
  defp which_vars(_), do: []
end

defmodule OtherThing do
  require Thing

  # def sleep_5(), do: :timer.sleep(5_000)
  def sleep_5(), do: :ok

  def myfunc(a \\ 1) do
    Thing.async with a <- a,
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
