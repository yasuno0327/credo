defmodule Credo.CLI.Task.RunAutofix do
  @moduledoc """
  Autocorrect issues.
  """

  use Credo.Execution.Task

  def call(exec, opts, read_fun \\ &File.read!/1, write_fun \\ &File.write!/2) do
    case exec.autofix do
      true ->
        issues = Keyword.get_lazy(opts, :issues, fn -> Execution.get_issues(exec) end)

        issues
        |> group_by_file()
        |> Enum.each(fn {file_path, issues} ->
          file = read_fun.(file_path)
          if file_path == "apps/neon/lib/neon_web/controllers/item_controller.ex" do
            {corrected, _shift} = Enum.reduce(issues, {file, 0}, fn issue, acc ->
              run_autofix(issue, acc, exec)
            end)

            corrected |> IO.puts()
            # write_fun.(file_path, corrected)
          end
          # write_fun.(file_path, corrected)
        end)

        exec
      _disabled -> exec
    end
  end

  defp group_by_file(issues) do
    Enum.reduce(issues, %{}, fn issue, acc ->
      Map.update(acc, issue.filename, [issue], &[issue | &1])
    end)
  end

  defp run_autofix(issue, {file, _line_shift} = acc, _exec) do
    case issue.check.autofix(acc, issue) do
      {^file, _line_shift} -> acc
      corrected ->
        # Execution.remove_issue(exec, issue)
        corrected
    end
  end
end
