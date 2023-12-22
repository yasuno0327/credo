
defmodule Credo.Check.Readability.Specs.SuccessTyping do
  def suggest(active_plt, module, function, line_no) do
    for {{mod, fun, arity}, success_typing} <- success_typings(active_plt, module) do
      line = find_function_line(mod, fun, arity)
      {{mod, fun, arity}, line, success_typing}
    end
    |> find_target(module, function, line_no)
  end

  defp success_typings(plt, module) do
    case :dialyzer_plt.lookup_module(plt, module) do
      {:value, list} ->
        for {{module, fun, arity}, ret, args} <- list do
          t = :erl_types.t_fun(args, ret)
          sig = :dialyzer_utils.format_sig(t)
          {{module, fun, arity}, sig}
        end
    end
  end

  defp find_function_line(module, fun, arity) do
    case ElixirSense.Core.Normalized.Code.get_docs(module, :docs) do
      nil ->
        nil

      docs ->
        Enum.find_value(docs, fn
          {{^fun, ^arity}, line, _, _, _, _meta} -> line
          _ -> nil
        end)
    end
  end

  defp find_target(success_typing_with_line, module, function, line_no) do
    Enum.find_value(success_typing_with_line, fn
      # TODO: 実際の関数の位置とElixirSense.Core.Normalized.Code.get_docsから取得してきた行番号がnilの場合がある
      # line_noではなくarityでパターンマッチすると良い...?
      {{^module, ^function, _arity}, _line_no, success_typing} ->
        success_typing
      _ -> nil
    end)
  end
end
