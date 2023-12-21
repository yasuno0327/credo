defmodule Credo.Check.Readability.Specs do
  use Credo.Check,
    tags: [:controversial],
    param_defaults: [
      include_defp: false
    ],
    explanations: [
      check: """
      Functions, callbacks and macros need typespecs.

      Adding typespecs gives tools like Dialyzer more information when performing
      checks for type errors in function calls and definitions.

          @spec add(integer, integer) :: integer
          def add(a, b), do: a + b

      Functions with multiple arities need to have a spec defined for each arity:

          @spec foo(integer) :: boolean
          @spec foo(integer, integer) :: boolean
          def foo(a), do: a > 0
          def foo(a, b), do: a > b

      The check only considers whether the specification is present, it doesn't
      perform any actual type checking.

      Like all `Readability` issues, this one is not a technical concern.
      But you can improve the odds of others reading and liking your code by making
      it easier to follow.
      """,
      params: [
        include_defp: "Include private functions."
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    specs = Credo.Code.prewalk(source_file, &find_specs(&1, &2))

    Credo.Code.prewalk(source_file, &traverse(&1, &2, specs, issue_meta))
  end

  # メモ
  # defmacro __using__ do, quote do...のように多重ブロック内に定義されている関数は外側の
  # __MODULE__.__using__などがissue.scopeに入ってしまい、バグる(target_modulesから見つからずにnilになる)
  # issueの発行段階(上記38行目)でのバグであり、直すにはcredo側にissueを立てる必要がある
  def autofix({file, line_shift}, issue) do
    active_plt = __MODULE__.Plt.load_plt()
    %{scope: scope, line_no: line_no} = issue
    {module, function} = split_module_function(scope)
    file_each_lines = String.split(file, "\n")

    suggest_spec_str =
      case module_beam_file(module) do
        nil ->
          nil
        beam_file ->
          active_plt
          |> __MODULE__.Plt.analyze_file(beam_file)
          |> __MODULE__.SuccessTyping.suggest(module, function, line_no)
          |> __MODULE__.Translator.translate_spec(module, function)
      end

    case suggest_spec_str do
      nil ->
        IO.puts("Cannot analyze function of #{module}.#{function}, line: #{line_no}")
        {file, line_shift}
      spec ->
        IO.puts("Autocorrected #{module}.#{function}, line: #{line_no}")
        spec_line_count = spec |> String.split("\n") |> length()
        function_line_index = line_no + line_shift - 1
        function_line = file_each_lines |> Enum.at(function_line_index)
        spec = __MODULE__.Translator.indent_spec(spec, function_line)
        updated_file = insert_to_file(spec, file_each_lines, function_line_index)

        {updated_file, line_shift + spec_line_count}
    end
  end

  defp split_module_function(scope) do
    splits = String.split(scope, ".")
    function = List.last(splits) |> String.to_atom()
    module =
      splits
      |> List.delete_at(-1)
      |> Module.concat()
    {module, function}
  end

  defp module_beam_file(module) do
    target_modules()
    |> Map.fetch(module)
    |> case do
      {:ok, beam_file} -> beam_file
      _ -> nil
    end
  end

  defp target_modules do
    beam_wildcard = "**/*.beam"
    build_path = Mix.Project.build_path()
    [build_path, beam_wildcard]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn beam_path, acc ->
      mod =
        beam_path
        |> Path.basename(".beam")
        |> String.to_atom
      Map.put(acc, mod, to_charlist(beam_path))
    end)
  end

  defp insert_to_file(spec, file_each_lines, insert_position) do
    file_each_lines
    |> List.insert_at(insert_position, spec)
    |> Enum.join("\n")
  end

  defp find_specs(
         {:spec, _, [{:when, _, [{:"::", _, [{name, _, args}, _]}, _]} | _]} = ast,
         specs
       ) do
    {ast, [{name, length(args)} | specs]}
  end

  defp find_specs({:spec, _, [{_, _, [{name, _, args} | _]}]} = ast, specs)
       when is_list(args) or is_nil(args) do
    args = with nil <- args, do: []
    {ast, [{name, length(args)} | specs]}
  end

  defp find_specs({:impl, _, [impl]} = ast, specs) when impl != false do
    {ast, [:impl | specs]}
  end

  defp find_specs({keyword, meta, [{:when, _, def_ast} | _]}, [:impl | specs])
       when keyword in [:def, :defp] do
    find_specs({keyword, meta, def_ast}, [:impl | specs])
  end

  defp find_specs({keyword, _, [{name, _, nil}, _]} = ast, [:impl | specs])
       when keyword in [:def, :defp] do
    {ast, [{name, 0} | specs]}
  end

  defp find_specs({keyword, _, [{name, _, args}, _]} = ast, [:impl | specs])
       when keyword in [:def, :defp] do
    {ast, [{name, length(args)} | specs]}
  end

  defp find_specs(ast, issues) do
    {ast, issues}
  end

  # TODO: consider for experimental check front-loader (ast)
  defp traverse(
         {keyword, meta, [{:when, _, def_ast} | _]},
         issues,
         specs,
         issue_meta
       )
       when keyword in [:def, :defp] do
    traverse({keyword, meta, def_ast}, issues, specs, issue_meta)
  end

  defp traverse(
         {keyword, meta, [{name, _, args} | _]} = ast,
         issues,
         specs,
         issue_meta
       )
       when is_list(args) or is_nil(args) do
    args = with nil <- args, do: []

    if keyword not in enabled_keywords(issue_meta) or {name, length(args)} in specs do
      {ast, issues}
    else
      {ast, [issue_for(issue_meta, meta[:line], name) | issues]}
    end
  end

  defp traverse(ast, issues, _specs, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Functions should have a @spec type specification.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp enabled_keywords(issue_meta) do
    issue_meta
    |> IssueMeta.params()
    |> Params.get(:include_defp, __MODULE__)
    |> case do
      true -> [:def, :defp]
      _ -> [:def]
    end
  end
end
