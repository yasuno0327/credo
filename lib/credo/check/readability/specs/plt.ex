defmodule Credo.Check.Readability.Specs.Plt do

  require Record

  @default_warns [
    :warn_behaviour,
    :warn_bin_construction,
    :warn_callgraph,
    :warn_contract_range,
    :warn_contract_syntax,
    :warn_contract_types,
    :warn_failing_call,
    :warn_fun_app,
    :warn_map_construction,
    :warn_matching,
    :warn_non_proper_list,
    :warn_not_called,
    :warn_opaque,
    :warn_return_no_exit,
    :warn_undefined_callbacks
  ]

  Record.defrecordp(
    :analysis_26,
    :analysis,
    analysis_pid: :undefined,
    type: :succ_typings,
    defines: [],
    doc_plt: :undefined,
    files: [],
    include_dirs: [],
    start_from: :byte_code,
    plt: :undefined,
    use_contracts: true,
    behaviours_chk: false,
    timing: false,
    timing_server: :none,
    callgraph_file: [],
    mod_deps_file: [],
    solvers: :undefined
  )

  def load_plt do
    plt_path()
    |> to_charlist()
    |> :dialyzer_cplt.from_file()
  rescue
    _ -> build_plt()
  catch
    _ -> build_plt()
  end

  def plt_path do
    Path.join([Mix.Utils.mix_home(), "credo-autofix-#{otp_vsn()}_elixir-#{System.version()}.plt"])
  end

  def analyze_file(active_plt, file) do
    analysis_config = analysis_26(plt: active_plt, files: [file], solvers: [])
    parent = self()

    pid =
      spawn_link(fn ->
        :dialyzer_analysis_callgraph.start(parent, @default_warns, analysis_config)
      end)

    main_loop(pid)
  end

  defp otp_vsn do
    major = :erlang.system_info(:otp_release) |> List.to_string()
    vsn_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])
    {:ok, contents} = File.read(vsn_file)
    String.split(contents, ["\r\n", "\r", "\n"], trim: true)
  end

  @elixir_apps [:elixir, :ex_unit, :mix, :iex, :logger, :eex]
  @erlang_apps [:erts, :kernel, :stdlib, :compiler]

  # from: elixir-ls/apps/language_server/lib/language_server/dialyzer/manifest.ex
  defp build_plt do
    IO.puts("Building PLT...")
    modules_to_paths =
      for app <- @erlang_apps ++ @elixir_apps,
        path <- beam_paths(app),
        into: %{},
        do: {pathname_to_module(path), String.to_charlist(path)}

    modules =
      modules_to_paths
      |> Map.keys()
      |> expand_references()

    files =
      for mod <- modules,
      path = modules_to_paths[mod] || get_beam_file(mod),
      is_list(path),
      do: path

    plt_path()
    |> Path.dirname()
    |> File.mkdir_p!()

    plt_path_of_charlist = plt_path() |> to_charlist()

    :dialyzer.run(
      analysis_type: :plt_build,
      files: files,
      from: :byte_code,
      output_plt: plt_path_of_charlist
    )

    :dialyzer_cplt.from_file(plt_path_of_charlist)
  end

  defp beam_paths(app) do
    [Application.app_dir(app), "**/*.beam"]
    |> Path.join()
    |> Path.wildcard()
  end

  defp pathname_to_module(path) do
    path
    |> Path.basename(".beam")
    |> String.to_atom()
  end

  def expand_references(modules, exclude \\ MapSet.new(), result \\ MapSet.new())

  def expand_references([], _, result) do
    result
  end

  def expand_references([module | rest], exclude, result) do
    result =
      if module in result or module in exclude or not dialyzable?(module) do
        result
      else
        result = MapSet.put(result, module)
        expand_references(module_references(module), exclude, result)
      end

    expand_references(rest, exclude, result)
  end

  defp module_references(mod) do
    try do
      for form <- read_forms(mod),
          {:call, _, {:remote, _, {:atom, _, module}, _}, _} <- form,
          uniq: true,
          do: module
    rescue
      _ -> []
    catch
      _ -> []
    end
  end

  defp dialyzable?(module) do
    file = get_beam_file(module)

    is_list(file) and match?({:ok, _}, :dialyzer_utils.get_core_from_beam(file))
  end

  defp get_beam_file(module) do
    case :code.which(module) do
      [_ | _] = file ->
        file

      other ->
        case :code.get_object_code(module) do
          {_module, _binary, beam_filename} -> beam_filename
          :error -> other
        end
    end
  end

  # Read the Erlang abstract forms from the specified Module
  # compiled using the -debug_info compile option
  defp read_forms(module) do
    case :beam_lib.chunks(:code.which(module), [:abstract_code]) do
      {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, forms}}]}} ->
        forms

      {:ok, {:no_debug_info, _}} ->
        throw({:forms_not_found, module})

      {:error, :beam_lib, {:file_error, _, :enoent}} ->
        throw({:module_not_found, module})
    end
  end

  defp main_loop(backend_pid) do
    receive do
      {^backend_pid, :done, new_plt, _new_doc_plt} ->
        new_plt

      {:EXIT, ^backend_pid, {:error, reason}} ->
        IO.inspect(reason)

      {:EXIT, ^backend_pid, reason} when reason != :normal ->
        IO.inspect(reason)

      _ ->
        main_loop(backend_pid)
    end
  end
end
