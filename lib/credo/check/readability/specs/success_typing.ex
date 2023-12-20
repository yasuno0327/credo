
defmodule Credo.Check.Readability.Specs.SuccessTyping do
  def suggest(active_plt, module) do
    for {{mod, fun, arity} = mfa, success_typing} <- success_typings(active_plt, module), :dialyzer_plt.lookup_contract(active_plt, mfa) do
      line = find_function_line(mod, fun, arity)
      {{mod, fun, arity}, line, success_typing}
    end
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
end
