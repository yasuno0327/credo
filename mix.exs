defmodule Credo.Mixfile do
  use Mix.Project

  @version "1.6.7"

  def project do
    [
      app: :credo,
      version: @version,
      elixir: ">= 1.7.0",
      escript: [main_module: Credo.CLI],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test, "test.fast": :test],
      name: "Credo",
      description: "A static code analysis tool with a focus on code consistency and teaching.",
      package: package(),
      source_url: "https://github.com/rrrene/credo",
      docs: docs(),
      aliases: aliases()
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "overview",
      logo: "assets/credo-logo-with-trail.png",
      extra_section: "GUIDES",
      assets: "guides/assets",
      formatters: ["html"],
      nest_modules_by_prefix: nest_modules_by_prefix(),
      groups_for_modules: groups_for_modules(),
      extras: extras(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp nest_modules_by_prefix do
    [
      Credo.Check.Design,
      Credo.Check.Readability,
      Credo.Check.Refactor,
      Credo.Check.Warning,
      Credo.Check.Consistency
    ]
  end

  defp extras do
    [
      "CHANGELOG.md",

      # Introduction

      "guides/introduction/overview.md",
      "guides/introduction/installation.md",
      "guides/introduction/basic_usage.md",
      "guides/introduction/exit_statuses.md",
      "guides/introduction/mix_tasks.md",

      # Commands

      "guides/commands/suggest_command.md",
      "guides/commands/diff_command.md",
      "guides/commands/explain_command.md",
      "guides/commands/list_command.md",

      # Checks

      "guides/custom_checks/adding_checks.md",
      "guides/custom_checks/testing_checks.md",

      # Configuration

      "guides/configuration/config_file.md",
      "guides/configuration/cli_switches.md",
      "guides/configuration/config_comments.md",
      "guides/configuration/check_params.md",

      # Plugins

      "guides/plugins/using_plugins.md",
      "guides/plugins/creating_plugins.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Configuration: ~r/guides\/configuration\//,
      Commands: ~r/guides\/commands\//,
      "Custom Checks": ~r/guides\/custom_checks\//,
      Plugins: ~r/guides\/plugins\//
    ]
  end

  defp groups_for_modules do
    [
      "Essential Behaviours": ~r/^Credo\.(Check|Plugin)$/,
      "Essential Structs": ~r/^Credo\.(Execution|Issue|IssueMeta|SourceFile)$/,
      "Code Analysis": ~r/^Credo\.Code(\.[^\.]+|)$/,
      "Testing Utilities": ~r/^Credo\.Test\./,
      "Check Utilities": ~r/^Credo\.Check(\.[^\.]+|)$/,
      "Checks: Software Design": ~r/^Credo\.Check\.Design\./,
      "Checks: Code Readability": ~r/^Credo\.Check\.Readability\./,
      "Checks: Refactoring Opportunities": ~r/^Credo\.Check\.Refactor\./,
      "Checks: Warnings": ~r/^Credo\.Check\.Warning\./,
      "Checks: Consistency": ~r/^Credo\.Check\.Consistency\./,
      "Commands & CLI": ~r/^Credo\.CLI(\.[^\.]+|)$/,
      Internal: ~r/^Credo\..+/
    ]
  end

  defp package do
    [
      files: [
        ".credo.exs",
        ".template.check.ex",
        ".template.debug.html",
        "lib",
        "LICENSE",
        "mix.exs",
        "README.md"
      ],
      maintainers: ["René Föhring"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/rrrene/credo",
        "Changelog" => "https://github.com/rrrene/credo/blob/master/CHANGELOG.md"
      }
    ]
  end

  def application do
    [
      mod: {Credo.Application, []},
      extra_applications: [:bunt, :crypto, :eex, :ex_unit, :file_system, :inets, :jason, :logger]
    ]
  end

  defp deps do
    [
      {:file_system, "~> 0.2.8"},
      {:bunt, "~> 0.2.1"},
      {:jason, "~> 1.0"},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:inch_ex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", runtime: false},
      {:elixir_sense, github: "elixir-lsp/elixir_sense", ref: "02c101d03c0b5a81379b3905e7baa6e685c0fe99"},
      {:erl2ex_vendored, github: "elixir-lsp/erl2ex", ref: "073ac6b9a44282e718b6050c7b27cedf9217a12a"}
    ]
  end

  defp aliases do
    [
      test: "test --exclude slow --include slow:disk_io",
      "test.fast": "test --exclude slow",
      "test.slow": "test --include slow"
    ]
  end
end
