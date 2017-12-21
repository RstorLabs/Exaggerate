defmodule Exaggerate.Codesynth do

  @project_root Path.relative_to_cwd("../../") |> Path.expand

  def swaggerfile_exists?(""), do: false
  def swaggerfile_exists?(filename), do: @project_root |> Path.join(filename) |> File.exists?
  def swaggerfile_isvalid?(filename) do
    swaggerfile_exists?(filename) && (@project_root |> Path.join(filename)
      |> File.read!
      |> Poison.decode!
      |> Exaggerate.Validation.OpenAPI.is_valid?)
  end

  def build_routes(routelist, modulename) when is_map(routelist) do
    routelist |> Map.keys
      |> Enum.map(fn route ->
        routelist[route] |> Map.keys
          |> Enum.map(fn verb ->
            verb |> String.to_atom
                 |> Exaggerate.Codesynth.Routesynth.build_route(route, routelist[route][verb], modulename)
          end)
      end) |> List.flatten
           |> Enum.join("\n\n")
  end

  def build_endpoints(routelist, modulename, defs_to_ignore) when is_map(routelist) do
    routelist |> Map.keys
      |> Enum.filter(fn x -> !(x in defs_to_ignore) end)
      |> Enum.map(fn route ->
        routelist[route] |> Map.keys
          |> Enum.map(fn verb ->
            verb |> String.to_atom
                 |> Exaggerate.Codesynth.Endpointsynth.build_endpoint(route, routelist[route][verb], modulename)
          end)
      end) |> List.flatten
           |> Enum.join("\n\n")
  end

  def build_endpointmodule(swaggerfile, filename, modulename, defs_to_ignore \\ []) do
    endpointcode = build_endpoints(swaggerfile["paths"], modulename, defs_to_ignore)
    """
      defmodule #{modulename} do
        #{endpointcode}
      end
    """ |> Code.format_string! |> Enum.join
  end


  def build_routemodule(swaggerfile, filename, modulename) do
    routecode = build_routes(swaggerfile["paths"], modulename)
    optional_plugs = "" #for now.

    """
      #########################################################################
      #
      # --WARNING--
      #
      # this code is autogenerated.  Alterations to this code risk introducing
      # deviations to the supplied OpenAPI specification.  Please consider
      # modifying #{filename} instead of this file.
      #

      defmodule #{modulename}.Routes do
        use Plug.Router
        import Exaggerate.RouteFunctions

        #{optional_plugs}

        plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json],
                         pass:  ["*/*"],
                         json_decoder: Poison

        plug :match
        plug :dispatch

        #{routecode}

        match _, do: send_resp(conn, 404, "{'error':'unknown route'}")

      end
    """ |> Code.format_string! |> Enum.join
  end

  @doc """
    retrives function definitions from a code token array.

    iex> "defmodule A do\n  def a do\n  end\n  def b do\n  end\nend" |> Code.format_string! |> Exaggerate.Codesynth.get_defs #==>
    ["a", "b"]
  """
  def get_defs(arr), do: get_defs(arr, :no)
  def get_defs([], :no), do: []
  def get_defs(["  def" | tail], :no), do: get_defs([tail], :def)
  def get_defs([head | tail], :def), do: [String.trim(head) | get_defs(tail)]
  def get_defs([_head | tail], :no), do: get_defs(tail)

  def insert_code(new_functions, code_tokens) do
    new_code = Enum.slice(code_tokens, 0..-3) ++ [new_functions] ++ ["\n","end"]
    new_code |> Code.format_string! |> Enum.join
  end

  def buildswaggerfile(swaggerfile, update \\ false) do
    #first, find the .json extension
    modulename = (if String.match?(swaggerfile, ~r/.json$/), do: String.slice(swaggerfile, 0..-6), else: swaggerfile)
      |> String.capitalize

    moduledir = Path.join([@project_root, "lib", String.downcase(modulename)])

    swaggerfile_content = @project_root
      |> Path.join(swaggerfile)
      |> File.read!
      |> Poison.decode!

    route_content = swaggerfile_content
      |> build_routemodule(swaggerfile, modulename)


    #check to see if the module directory exists.
    if update do
      if !File.exists?(moduledir), do: raise("directory #{moduledir} does not exist; cannot update swaggerfile")
      if !File.dir?(moduledir),    do: raise("directory #{moduledir} does not exist; cannot update swaggerfile")

      routefile = Path.join(moduledir, String.downcase(modulename) <> ".ex")

      if !File.exists?(routefile), do: raise("file #{routefile} does not exist; cannot update swaggerfile")

      routefile_tokens = Code.format_file!(routefile)
        |> fn [a | _b] -> a end.()  #format_file! returns a list of a list of tokens and a second value, throw away this second value.

      endpoint_content = swaggerfile_content
        |> build_endpointmodule(swaggerfile, modulename, get_defs(routefile_tokens))
        |> insert_code(routefile_tokens)

      Path.join(moduledir, "routes.ex")
        |> File.write!(route_content)
      Path.join(moduledir, String.downcase(modulename) <> ".ex")
        |> File.write!(endpoint_content)

    else
      if File.exists?(moduledir), do: raise("directory #{moduledir} exists; cannot create swaggerfile")

      endpoint_content = swaggerfile_content
        |> build_endpointmodule(swaggerfile, modulename)

      File.mkdir!(moduledir)
      Path.join(moduledir, "routes.ex")
        |> File.write!(route_content)
      Path.join(moduledir, String.downcase(modulename) <> ".ex")
        |> File.write!(endpoint_content)
    end
  end
end
