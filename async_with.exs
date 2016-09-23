defmodule Thing do
  def thing({:with, _, withs}) do
    for weth <- withs, do: do_withs(weth)
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

expr = quote do
  with myvar <- 1,
       %{key: val, otherkey: otherval} <- %{key: 123},
       other_thing <- do_thing(myvar) do
    next_thing(other_thing)
    do_thing(myvar)
  end
end

IO.inspect Thing.thing(expr)

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
