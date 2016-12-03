defmodule Credo.CLI.Output.Explain do
  alias Credo.Code.Scope
  alias Credo.CLI.Filter
  alias Credo.CLI.Output
  alias Credo.CLI.Output.UI
  alias Credo.SourceFile
  alias Credo.Issue

  @indent 8

  @doc "Called before the analysis is run."
  def print_before_info(source_files, _config) do
    UI.puts
    case Enum.count(source_files) do
      0 -> UI.puts "No files found!"
      1 -> UI.puts "Checking 1 source file ..."
      count -> UI.puts "Checking #{count} source files ..."
    end
  end

  @doc "Called after the analysis has run."
  def print_after_info(source_file, config, line_no, column) do
    term_width = Output.term_columns

    print_issues(source_file, config, term_width, line_no, column)
  end

  defp print_issues(nil, _config, _term_width, _line_no, _column) do
    nil
  end

  defp print_issues(%SourceFile{issues: issues, filename: filename} = source_file, config, term_width, line_no, column) do
    issues
    |> Filter.important(config)
    |> Filter.valid_issues(config)
    |> Enum.sort_by(&(&1.line_no))
    |> filter_issues(line_no, column)
    |> print_issues(filename, source_file, config, term_width, line_no, column)
  end

  defp print_issues([], _filename, _source_file, _config, _term_width, _line_no, _column) do
    nil
  end

  defp print_issues(issues, _filename, source_file, _config, term_width, _line_no, _column) do
    first_issue = List.first(issues)
    scope_name = Scope.mod_name(first_issue.scope)
    color = Output.check_color(first_issue)
    output = [
      :bright, String.to_atom("#{color}_background" ), color, " ",
        Output.foreground_color(color), :normal,
      String.ljust(" #{scope_name}", term_width - 1),
    ]

    UI.puts
    UI.puts(output)
    UI.puts_edge(color)

    Enum.each(issues, &print_issue(&1, source_file, term_width))
  end

  defp filter_issues(issues, line_no, nil) do
    line_no = String.to_integer(line_no)
    Enum.filter(issues, &filter_issue(&1, line_no, nil))
  end
  defp filter_issues(issues, line_no, column) do
    line_no = String.to_integer(line_no)
    column = String.to_integer(column)

    Enum.filter(issues, &filter_issue(&1, line_no, column))
  end

  defp filter_issue(%Issue{line_no: a, column: b}, a, b), do: true
  defp filter_issue(%Issue{line_no: a}, a, _), do: true
  defp filter_issue(_, _, _), do: false

  defp print_issue(%Issue{check: check, message: message, filename: filename, priority: priority} = issue, source_file, term_width) do
    pos = pos_string(issue.line_no, issue.column)
    outer_color = Output.check_color(issue)
    inner_color = Output.check_color(issue)
    message_color  = inner_color
    filename_color = :default_color
    tag_style = if outer_color == inner_color, do: :faint, else: :bright

    category_output = [
      UI.edge(outer_color),
        inner_color,
        tag_style,
         "  ",
        Output.check_tag(check.category),
        :reset, " Category: #{check.category} "
    ]
    UI.puts(category_output)

    priority_output = [
      UI.edge(outer_color),
        inner_color,
        tag_style,
        "   ",
        Output.priority_arrow(priority),
        :reset, "  Priority: #{Output.priority_name(priority)} "
    ]
    UI.puts(priority_output)

    UI.puts_edge(outer_color)

    message_output = [
      UI.edge(outer_color),
        inner_color,
        tag_style,
        "    ",
        :normal, message_color, "  ", message,
    ]
    UI.puts(message_output)

    scope_output = [
      UI.edge(outer_color, @indent),
        filename_color, :faint, to_string(filename),
        :default_color, :faint, pos,
        :faint, " (#{issue.scope})"
    ]
    UI.puts(scope_output)

    if issue.line_no do
      UI.puts_edge([outer_color, :faint])

      question_output = [
        UI.edge([outer_color, :faint]), :reset, :color239,
          String.duplicate(" ", @indent - 5), "__ CODE IN QUESTION"
      ]
      UI.puts(question_output)

      UI.puts_edge([outer_color, :faint])

      code_color = :faint
      print_source_line(source_file, issue.line_no - 2, term_width, code_color, outer_color)
      print_source_line(source_file, issue.line_no - 1, term_width, code_color, outer_color)
      print_source_line(source_file, issue.line_no, term_width, [:cyan, :bright], outer_color)

      if issue.column do
        offset = 0
        x = max(issue.column - offset - 1, 0) # column is one-based
        w =
          case issue.trigger do
            nil -> 1
            atom -> atom |> to_string |> String.length
          end

        column_output = [
          UI.edge([outer_color, :faint], @indent),
            inner_color, String.duplicate(" ", x),
            :faint, String.duplicate("^", w)
        ]
        UI.puts(column_output)
      end
      print_source_line(source_file, issue.line_no + 1, term_width, code_color, outer_color)
      print_source_line(source_file, issue.line_no + 2, term_width, code_color, outer_color)
    end

    UI.puts_edge([outer_color, :faint], @indent)

    why_it_matters_output = [
      UI.edge([outer_color, :faint]), :reset, :color239,
        String.duplicate(" ", @indent - 5), "__ WHY IT MATTERS"
    ]
    UI.puts(why_it_matters_output)

    UI.puts_edge([outer_color, :faint])

    explanation = issue.check.explanation || "TODO: Insert explanation"

    explanation
    |> String.strip
    |> String.split("\n")
    |> Enum.flat_map(&format_explanation(&1, outer_color))
    |> Enum.slice(0..-2)
    |> UI.puts

    UI.puts_edge([outer_color, :faint])

    print_params_explanation(issue.check, outer_color)

    UI.puts_edge([outer_color, :faint])
  end

  defp print_source_line(%SourceFile{lines: lines}, line_no, _, _, _) when line_no < 1 or line_no > length(lines) do
    nil
  end
  defp print_source_line(%SourceFile{lines: lines}, line_no, term_width, color, outer_color) do
    {_, line} = Enum.at(lines, line_no - 1)

    line_no_str = String.rjust("#{line_no} ", @indent - 2)

    line_no_output = [
      UI.edge([outer_color, :faint]), :reset,
        :faint, line_no_str, :reset,
        color, UI.truncate(line, term_width - @indent)
    ]
    UI.puts(line_no_output)
  end

  def format_explanation(line, outer_color) do
    [
      UI.edge([outer_color, :faint], @indent),
      :reset, format_explanation_text(line),
      "\n"
    ]
  end
  def format_explanation_text("    " <> line) do
    [:yellow, :faint, "    ", line]
  end
  def format_explanation_text(line) do
    # TODO: format things in backticks in help texts
    #case Regex.run(~r/(\`[a-zA-Z_\.]+\`)/, line) do
    #  v ->
    #    # IO.inspect(v)
        [:reset, line]
    #end
  end

  defp pos_string(nil, nil), do: ""
  defp pos_string(line_no, nil), do: ":#{line_no}"
  defp pos_string(line_no, column), do: ":#{line_no}:#{column}"

  def print_params_explanation(nil, _), do: nil
  def print_params_explanation(check, outer_color) do
    keywords = check.explanation_for_params
    check_name = check |> to_string |> String.replace(~r/^Elixir\./, "")

    config_output = [
      UI.edge([outer_color, :faint]), :reset, :color239,
        String.duplicate(" ", @indent-5), "__ CONFIGURATION OPTIONS",
    ]
    UI.puts(config_output)

    UI.puts_edge([outer_color, :faint])

    if keywords |> List.wrap |> Enum.any? do
      keywords_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "To configure this check, use this tuple"
      ]
      UI.puts(keywords_output)

      UI.puts_edge([outer_color, :faint])

      params_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "  {", :cyan, check_name, :reset, ", ", :cyan, :faint, "<params>", :reset ,"}"
      ]
      UI.puts(params_output)

      UI.puts_edge([outer_color, :faint])

      additional_params_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "with ", :cyan, :faint, "<params>", :reset ," being ", :cyan, "false", :reset, " or any combination of these keywords:"
      ]
      UI.puts(additional_params_output)

      UI.puts_edge([outer_color, :faint])

      Enum.each(keywords, fn({param, text}) ->
        output = [
          UI.edge([outer_color, :faint]), :reset,
            String.duplicate(" ", @indent-2),
            :cyan, String.ljust("  #{param}:", 20),
            :reset, text
        ]
        UI.puts(output)
      end)
    else
      disable_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "You can disable this check by using this tuple"
      ]
      UI.puts(disable_output)

      UI.puts_edge([outer_color, :faint])

      edge_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "  {", :cyan, check_name, :reset, ", ", :cyan, "false", :reset ,"}"
      ]
      UI.puts(edge_output)

      UI.puts_edge([outer_color, :faint])

      config_output = [
        UI.edge([outer_color, :faint]), :reset,
          String.duplicate(" ", @indent-2), "There are no other configuration options."
      ]
      UI.puts(config_output)

      UI.puts_edge([outer_color, :faint])
    end
  end
end
