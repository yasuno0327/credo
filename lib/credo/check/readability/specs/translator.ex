defmodule Credo.Check.Readability.Specs.Translator do
  alias Erl2exVendored.Convert.{Context, ErlForms}
  alias Erl2exVendored.Pipeline.{Parse, ModuleData, ExSpec}

  def translate_spec(success_typing, module, function) do
    {[%ExSpec{specs: [spec]} | _rest], _} =
      # erl_parseを使っている都合上、erlangでの予約語などが入っているとエラーになる
      # そのため、一旦fooで置き換えている
      # ここで設定したfooは呼び出し元で元の関数名に戻る
      "-spec foo#{success_typing}."
      |> Parse.string()
      |> hd()
      |> elem(0)
      |> ErlForms.conv_form(%Context{in_type_expr: true, module_data: %ModuleData{}})

    spec
    |> Macro.postwalk(&tweak_specs/1)
    |> improve_defprotocol_spec(module, function)
    |> Macro.to_string()
    |> Code.format_string!(line_length: :infinity)
    |> IO.iodata_to_binary()
    |> String.replace_prefix("foo", to_string(function))
    |> then(&"@spec #{&1}")
  end

  @doc """
  To insert an indent to match the indentation of the target function line.
  """
  def indent_spec(spec_str, target_func_line) do
    space_num = count_indent(target_func_line)
    spaces = String.duplicate(" ", space_num)

    spec_str
    |> String.split("\n")
    |> Enum.map(&"#{spaces}#{&1}")
    |> Enum.join("\n")
  end

  defp count_indent(target_func_line) do
    target_func_line
    |> String.graphemes()
    |> Enum.reduce_while(0, fn character, count ->
      if character == " " do
        {:cont, count + 1}
      else
        {:halt, count}
      end
    end)
  end

  defp tweak_specs({:list, _meta, args}) do
    case args do
      [{:{}, _, [{:atom, _, []}, {wild, _, _}]}] when wild in [:_, :any] -> quote do: keyword()
      [{:{}, _, [{:atom, _, []}, other]}] -> quote do: keyword(unquote(other))
      [{:any, _, []}] -> quote do: list()
      list -> list
    end
  end

  defp tweak_specs({:nonempty_list, _meta, args}) do
    case args do
      [{:any, _, []}] -> quote do: [...]
      _ -> args ++ quote do: [...]
    end
  end

  defp tweak_specs({:%{}, _meta, fields}) do
    fields =
      Enum.map(fields, fn
        {:map_field_exact, _, [key, value]} -> {key, value}
        {key, value} -> quote do: {optional(unquote(key)), unquote(value)}
        field -> field
      end)

    translate_map(fields)
  end

  # Undo conversion of _ to any() when inside binary spec
  defp tweak_specs({:<<>>, _, children}) do
    children =
      Macro.postwalk(children, fn
        {:any, _, []} -> quote do: _
        other -> other
      end)

    {:<<>>, [], children}
  end

  defp tweak_specs({:_, _, _}) do
    quote do: any()
  end

  defp tweak_specs({:when, [], [spec, substitutions]}) do
    substitutions = Enum.reject(substitutions, &match?({:_, {:any, _, []}}, &1))

    case substitutions do
      [] -> spec
      _ -> {:when, [], [spec, substitutions]}
    end
  end

  defp tweak_specs([{:->, _, [[{:..., _, _}], {:any, _, []}]}]) do
    quote do: fun()
  end

  defp tweak_specs(node) do
    node
  end

  defp translate_map([
         {:__struct__, {:atom, _, []}},
         {{:optional, _, [{:atom, _, []}]}, {:any, _, []}}
       ]) do
    quote do: struct()
  end

  defp translate_map([
         {{:optional, _, [{:any, _, []}]}, {:any, _, []}}
       ]) do
    quote do: map()
  end

  defp translate_map(fields) do
    struct_type =
      fields
      |> Enum.find_value(fn
        {:__struct__, struct_type} when is_atom(struct_type) -> struct_type
        _ -> nil
      end)

    translate_map(struct_type, fields)
  end

  defp translate_map(nil, fields) do
    {:%{}, [], fields}
  end

  defp translate_map(struct_type, fields) do
    struct_type_spec_exists = struct_type_spec_exists?(struct_type)

    if struct_type_spec_exists do
      # struct_type.t/0 public/opaque type exists, assume it's a struct
      {{:., [], [struct_type, :t]}, [], []}
    else
      # translate map AST to struct AST
      fields = fields |> Enum.reject(&match?({:__struct__, _}, &1))
      map = {:%{}, [], fields}
      {:%, [], [struct_type, map]}
    end
  end

  defp struct_type_spec_exists?(struct_type) do
    ElixirSense.Core.Normalized.Typespec.get_types(struct_type)
    |> Enum.any?(&match?({kind, {:t, _, []}} when kind in [:type, :opaque], &1))
  end

  defp improve_defprotocol_spec(ast, mod, fun) do
    cond do
      Code.ensure_loaded?(mod) and function_exported?(mod, :__protocol__, 1) ->
        # defprotocol
        # defs in defprotocol do not have when and have at least 1 arg
        {:"::", [], [{:foo, [], [{:any, [], []} | rest]}, {:any, [], []}]} = ast
        # first arg in defprotocol defs is always of type t
        {:"::", [], [{:foo, [], [{:t, [], []} | rest]}, {:any, [], []}]}

      Code.ensure_loaded?(mod) and function_exported?(mod, :__impl__, 1) ->
        # defimpl
        implementation_of = mod.__impl__(:protocol)

        {:"::", [], [{:foo, [], args}, res]} = ast
        arity = length(args)

        if {fun, arity} in implementation_of.__protocol__(:functions) do
          # protocol fun
          implemented_for_type =
            case mod.__impl__(:for) do
              Any ->
                {:any, [], []}

              Atom ->
                {:atom, [], []}

              Integer ->
                {:integer, [], []}

              Float ->
                {:float, [], []}

              BitString ->
                {:binary, [], []}

              Map ->
                {:map, [], []}

              List ->
                {:list, [], []}

              Function ->
                {:function, [], []}

              Port ->
                {:port, [], []}

              PID ->
                {:pid, [], []}

              Tuple ->
                {:tuple, [], []}

              Reference ->
                {:reference, [], []}

              struct_type ->
                translate_map(struct_type, [])
            end

          {:"::", [], [{:foo, [], [implemented_for_type | tl(args)]}, res]}
        else
          # non protocol fun/macro
          ast
        end

      true ->
        ast
    end
  end
end