defmodule AsyncWith do
  # Macros

  @moduledoc """
  ## Literals

  Literals execute immediately, but still spawn a `Task`, so they will be much slower than a literal in a normal with

      iex> require AsyncWith
      iex> import AsyncWith
      iex> async with {:ok, a} <- {:ok, 5} do
      ...>   a
      ...> end
      5
      iex> with {:ok, a} <- {:ok, 5} do
      ...>   a
      ...> end
      5

  ## Errors

  A match error will be returned, like normal `with`, but it will still require a `Task` to produce the value, so it
  will be slower than a normal `with`.

      iex> require AsyncWith
      iex> import AsyncWith
      iex> async with {:ok, a} <- {:error, :reason} do
      ...>   a
      ...> end
      {:error, :reason}
      iex> with {:ok, a} <- {:error, :reason} do
      ...>   a
      ...> end
      {:error, :reason}

  `else` clauses for error handling still works with `async`

      iex> require AsyncWith
      iex> import AsyncWith
      iex> async with {:ok, a} <- {:error, :reason} do
      ...>   a
      ...> else
      ...>   {:error, reason} -> reason
      ...> end
      :reason
      iex> with {:ok, a} <- {:error, :reason} do
      ...>   a
      ...> else
      ...>   {:error, reason} -> reason
      ...> end
      :reason

  """
  defmacro async(expr, do: block), do: do_async(expr, block)

  # Functions

  ## Private Functions

  defp clean_vars(vars, replace \\ nil) do
    vars
    |> Enum.map_reduce(
         [],
         fn (var = {name, index}, acc) ->
           case name in acc do
             true -> {replace || {:_, index}, acc}
             false -> {var, [name|acc]}
           end
         end
       )
    |> elem(0)
  end

  defp collector_assignment(vars) do
    nothing = Enum.map(vars, fn _ -> :nothing end)
    cleaned_vars =
      vars
      |> clean_vars()
      |> Enum.reduce(
           nothing,
           fn ({var, index}, acc) ->
             List.replace_at(acc, index, var)
           end
         )

    vars_asts = for var <- cleaned_vars, do: Macro.var(var, nil)
    ast = {:{}, [], vars_asts}

    quote do
      unquote(ast) <- Task.await(collector, 30_000)
    end
  end

  defp collector_ast(vars) do
    quote do
      collector = Task.async fn ->
        loop = fn (state, fun) ->
          new_state = receive(do: unquote(receive_lines(vars)))

          case new_state do
            unquote(state_match_line(vars))
          end
        end

        loop.(unquote(Macro.escape nothing_tuple(vars)), loop)
      end
    end
  end

  defp collector_sends(lefts) do
    Enum.map lefts, fn ({var_name, var_index}) ->
      quote do
        send(collector.pid, {unquote(var_index), unquote(Macro.var(var_name, nil))})
      end
    end
  end

  defp do_async({:with, _, withs}, block) do
    weths = for weth <- withs, do: do_withs(weth)
    weths = Enum.reject(weths, &(&1 == []))

    {weths, _lefts} = Enum.map_reduce weths, [], fn (weth, acc) ->
      {lefts, rights, expr} = weth
      rights = Enum.uniq(rights)
      rights = Enum.filter(rights, &(&1 in acc))

      {{lefts, rights, expr}, lefts ++ acc}
    end

    {weths, {_, vars}} = Enum.map_reduce weths, {-1, []}, fn(weth, acc) ->
      {lefts, rights, expr} = weth
      {index, current_lefts} = acc
      rights = Enum.map(rights, fn(x) -> {x, Keyword.get(current_lefts, x)} end)
      {lefts, index} = Enum.map_reduce(lefts, index, &({{&1, &2 + 1}, &2 + 1}))
      current_lefts = lefts ++ current_lefts

      {{lefts, rights, expr}, {index, current_lefts}}
    end

    col_ast = collector_ast(vars)
    t_ast = tasks_ast(weths)

    quote do
      unquote(col_ast)
      unquote(t_ast)

      with unquote(collector_assignment(vars)) do
        unquote(block)
      end
    end
  end

  defp do_which_vars(ast) do
    {_, acc} = Macro.prewalk(ast, [], fn x, acc -> {x, which_vars(x) ++ acc} end)
    acc
  end

  defp do_withs(expr = {:<-, _, [left, right]}) do
    {do_which_vars(left), do_which_vars(right), expr}
  end
  defp do_withs(otherwise), do: []

  defp expanding_nothing_tuple(vars) do
    case vars do
      [] -> {}
      vars ->
        highest = vars
                  |> Enum.max_by(fn({_, index}) -> index end)
                  |> elem(1)

        nothings = 0..highest
                   |> Enum.to_list()
                   |> Enum.map(fn _ -> {:ok, :nothing} end)

        vars
        |> Enum.reduce(
             nothings,
             fn ({var, index}, acc) ->
               List.replace_at(acc, index, :nothing)
             end
           )
        |> List.to_tuple()
    end
  end

  defp nothing_tuple(vars) do
    vars
    |> Enum.map(fn _ -> :nothing end)
    |> List.to_tuple()
  end

  defp receive_lines(vars) do
    clauses = Enum.flat_map vars, fn ({_var, index}) ->
      quote do
        {unquote(index), val} -> put_elem(state, unquote(index), {:ok, val})
      end
    end

    abort = quote do
      return = {:abort, _return} -> return
    end

    abort ++ clauses
  end

  defp right_vars_with_clauses(rights) do
    for {name, index} <- rights do
      quote do
        unquote(Macro.var(name, nil)) = elem(return, unquote(index))
      end
    end
  end

  defp state_match_line(vars) do
    nothing = case vars do
      [] -> []
      vars ->
        highest = vars
                  |> Enum.max_by(fn({_, index}) -> index end)
                  |> elem(1)
        Enum.map(0..highest |> Enum.to_list(), fn _ -> :nothing end)
    end

    new_vars = vars
               |> clean_vars({:nothing, -1})
               |> Enum.reduce(
                    nothing,
                    fn ({var, index}, acc) ->
                      case (-1 == index) do
                        true -> acc
                        false -> List.replace_at(acc, index, var)
                      end
                    end
                  )

    vars_ast = for var <- new_vars, do: var == :nothing || Macro.var(var, nil)

    cleaned_vars = vars
                   |> clean_vars()
                   |> Enum.reduce(
                        nothing,
                        fn ({var, index}, acc) ->
                          List.replace_at(acc, index, var)
                        end
                      )

    oks_vars = for var <- cleaned_vars, do: {:ok, Macro.var(var, nil)}
    oks = {:{}, [], oks_vars}
    vars_tuple = {:{}, [], vars_ast}

    quote do
      {:abort, return} -> return
      unquote(oks) -> unquote(vars_tuple)
      _ -> fun.(new_state, fun)
    end
  end

  defp task_ast(index, right_vars, clause, sends, left_vars) do
    quote do
      tasks = put_elem tasks, unquote(index), Task.start fn ->
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
      end
    end
  end

  defp task_sends(sends) do
    Enum.map sends, fn ({var_index, var_name, task_index}) ->
      quote do
        send(elem(tasks, unquote(task_index)) |> elem(1),
          {unquote(var_index), unquote(Macro.var(var_name, nil))})
      end
    end
  end

  defp tasks_ast(weths = [{_lefts, _rights, _expr}|_rest]) do
    tasks_tuple = 1..(length(weths))
                  |> Enum.to_list()
                  |> List.to_tuple()

    asts = for {{lefts, rights, expr}, index} <- Enum.with_index(weths) do
      sends = weths
              |> Enum.with_index()
              |> Enum.map(
                   fn ({{_lefts, rights, _}, index}) ->
                     {rights -- (rights -- lefts), index}
                   end
                 )
              |> Enum.filter(fn ({deps, _index}) -> deps != [] end)
              |> Enum.flat_map(
                   fn ({deps, task_index}) ->
                     Enum.map deps, fn ({var_name, var_index}) ->
                       {var_index, var_name, task_index}
                     end
                   end
                 )

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

  defp tasks_send_abort do
    quote do
      Enum.map Tuple.to_list(tasks), fn(task) ->
        task
        |> elem(1)
        |> Process.exit(:with_abort)
      end
    end
  end

  defp wait_receive(vars) do
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

  defp which_vars({name, meta, context}) when is_atom(context) do
    [name]
  end
  defp which_vars(_), do: []
end
