defmodule Exaggerate.Codesynth.Routesynth do

  @doc """
    the master function which creates a routemodule file from a swagger file.
  """
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

  @doc """
    Exaggerate.Codesynth.Routesynth.get_summary(m::Map)
    retrieves a summary value from a route definition, if it exists.  The value
    is the textual equivalent of an elixir comment.  Otherwise returns an empty
    string.  Also handles blank string summaries as no comment.

    # Examples

    iex> Exaggerate.Codesynth.Routesynth.get_summary(%{"summary" => "this is a summary comment"}) #==>
    "# this is a summary comment"
    iex> Exaggerate.Codesynth.Routesynth.get_summary(%{"dummy" => "this is a dummy parameter"})   #==>
    ""
    iex> Exaggerate.Codesynth.Routesynth.get_summary(%{"summary" => ""})                          #==>
    ""
  """
  def get_summary(%{"summary" => ""}), do: ""
  def get_summary(%{"summary" => summary}), do: "# #{summary}"
  def get_summary(%{}), do: ""

  def regexp_for_pathsub(%{"in" => "path", "name" => name}), do: {"{#{name}}",":#{name}"}
  def regexp_for_pathsub(%{}), do: nil

  @doc """
    takes all of the parameters which are path parameters and converts them from
    swagger-style bracketed values and turns them into sinatra/plug style colon
    sigil values.

    # Example

    iex> Exaggerate.Codesynth.Routesynth.substitute_pathparams("/route/{param}", [%{"in" => "path", "name" => "param"}]) #==>
    "/route/:param"
  """
  def substitute_pathparams(pathstring, nil), do: pathstring
  def substitute_pathparams(pathstring, parameters) do
    parameters |> Enum.map(&Exaggerate.Codesynth.Routesynth.regexp_for_pathsub/1)
               |> Enum.filter(& &1)
               |> Enum.reduce(pathstring, fn {bracketval, colonval}, str -> String.replace(str, bracketval, colonval) end)
  end

  @doc """
    determines the default response from the response map.  This might be overridden
    by the "default" keyword, but otherwise, we draw it from the content returned
    from the {:ok, content} response of the operationId function.
  """
  def get_default_response(%{"default" => default_value}), do: "_ -> send_formatted(conn, 200, #{inspect default_value})"
  def get_default_response(%{}), do: "{:ok, content} -> send_formatted(conn, 200, content)\n_ -> send_resp(conn, 400, \"\")"

  ##############################################################################
  ## non-error alternate response codes.

  def get_responses(response_map = %{}, fun) do
    Map.keys(response_map)
      |> Enum.map(fn key -> fun.(key, response_map[key]) end)
      |> Enum.filter(& &1)  #removes nils
      |> Enum.join("\n")
  end

  ##############################################################################
  ## error responses
  def get_response(http_code = "2" <> <<_::size(16)>>, response_map = %{"description" => response_desc}) do
    #check that this error_val corresponds to a http response number.
    {_number, _} = Integer.parse(http_code)
    #figure out content validation later, using compile-time schemas.
    """
    #handles #{response_desc}.
    {:ok, #{http_code}, details} -> send_formatted(conn, #{http_code}, %{\"#{http_code}\" => \"#{response_desc}: \" <> details})
    """
  end
  def get_response(error_code = "4" <> <<_::size(16)>>, _error_map = %{"description" => error_desc}) do
    #check that this error_val corresponds to a http response number.
    {_number, _} = Integer.parse(error_code)
    #a simple error reporting, using the description.
    """
    #handles #{error_desc}.
    {:error, #{error_code}, details} -> send_formatted(conn, #{error_code}, %{\"#{error_code}\" => \"#{error_desc}: \" <> details})
    """
  end
  def get_response(_, _), do: nil

  ##############################################################################
  ## parameter lists

  @doc """
    checks if there are any required elements in the parameters list, which will
    trigger a with block in the elixir code.
  """
  def needs_with_block?(%{"required" => true, "in" => "path"}), do: false
  def needs_with_block?(%{"required" => true}), do: true
  def needs_with_block?(%{}), do: false
  def needs_with_block?([]), do: false
  def needs_with_block?([head | tail]), do: needs_with_block?(head) || needs_with_block?(tail)
  def needs_with_block?(nil), do: false

  def required_param_or_nil(%{"required" => true, "name" => name}), do: name
  def required_param_or_nil(%{}), do: nil
  def optional_param_or_nil(%{"required" => true}), do: nil
  def optional_param_or_nil(%{"name" => name}), do: "\"#{name}\" => #{name}"

  def required_params([]), do: nil
  def required_params(list) do
    list |> Enum.map(&Exaggerate.Codesynth.Routesynth.required_param_or_nil/1)
         |> Enum.filter(& &1)
         |> Enum.join(",")
  end
  def optional_params([]), do: nil
  def optional_params(list) do
    list |> Enum.map(&Exaggerate.Codesynth.Routesynth.optional_param_or_nil/1)
         |> Enum.filter(& &1)
         |> Enum.join(",")
  end

  @doc """
    gets a textual version of a parameters list, with the optional parameters
    enclosed in a hash bracket.  Presumes a "conn" variable in the params list
    prior to the desired parameters.

    # Examples

    iex> Exaggerate.Codesynth.Routesynth.get_params_list(nil)                                          #==>
    ""

    iex> Exaggerate.Codesynth.Routesynth.get_params_list([%{"required" => true, "name" => "test"}])    #==>
    ",test"

  """
  def get_params_list(nil), do: ""
  def get_params_list(list) do
    {required_params(list), optional_params(list)} |> fn
      {nil, nil} -> ""
      {"", ""}   -> ""
      {"", op}   -> "," <> "%{#{op}}"
      {rp, ""}   -> "," <> rp
      {rp, op}   -> "," <> rp <> "," <> "%{#{op}}"
    end.()
  end

  ##############################################################################
  ## consider refactoring the following functions to operate on lists with nils.

  def get_parameter_fetch_function(%{"in" => "path", "name" => _name}), do: nil
  def get_parameter_fetch_function(%{"in" => location, "name" => name, "required" => true}) when is_binary(location), do: "#{location}_parameter(conn, \"#{name}\", :required)"
  def get_parameter_fetch_function(%{"in" => location, "name" => name}) when is_binary(location), do: "#{location}_parameter(conn, \"#{name}\")"

  def get_checked_param_fetch(%{"required" => true, "in" => "path"}), do: nil
  def get_checked_param_fetch(param = %{"required" => true, "name" => name}), do: "{:ok, #{name}} <- " <> get_parameter_fetch_function(param)
  def get_checked_param_fetch(%{}), do: nil
  def get_checked_param_fetch(nil), do: ""
  def get_checked_param_fetch(arr) when is_list(arr) do
    arr |> Enum.map(&Exaggerate.Codesynth.Routesynth.get_checked_param_fetch/1)
        |> Enum.filter(& &1)
        |> Enum.join(",\n")
  end

  def get_basic_param_fetch(%{"required" => true}), do: nil  #also filters out path parameters
  def get_basic_param_fetch(param = %{"name" => name}), do: name <> " = " <> get_parameter_fetch_function(param)
  def get_basic_param_fetch(%{}), do: nil
  def get_basic_param_fetch(nil), do: ""
  def get_basic_param_fetch(arr) when is_list(arr) do
    arr |> Enum.map(&Exaggerate.Codesynth.Routesynth.get_basic_param_fetch/1)
        |> Enum.filter(& &1)
        |> Enum.join("\n")
  end

  def build_route(verb, route, route_def, routemodule) when is_atom(verb) and is_binary(route) and is_map(route_def) do
    unless Map.has_key?(route_def, "operationId"), do: raise "Exaggerate requires operationIds for all routes."

    verb_string = Atom.to_string(verb)
    route_string = substitute_pathparams(route, route_def["parameters"])
    #is not required by the swagger spec, but is required by exaggerate.
    operation = route_def["operationId"]

    #responses is required.  Check if there's a default response, if there is,
    #it will override the {:ok, content} possibility.
    default_code = get_default_response(route_def["responses"])
    summary      = get_summary(route_def)
    code_paths   = get_responses(route_def["responses"], &get_response/2)

    params_list  = get_params_list(route_def["parameters"])
    params_check = needs_with_block?(route_def["parameters"])
    checked_params = if params_check, do: """
      with #{get_checked_param_fetch(route_def["parameters"])} do
    """, else: ""
    basic_params = get_basic_param_fetch(route_def["parameters"])
    params_close = if params_check, do: """
    else
      {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
    end
    """, else: ""

    """
    #{verb_string} "#{route_string}" do
      #{summary}
      #{checked_params}
      #{basic_params}
      case #{routemodule}.#{operation}(conn#{params_list}) do
        #{code_paths}
        #{default_code}
      end
      #{params_close}
    end
    """ |> Code.format_string! |> Enum.join
  end
end
