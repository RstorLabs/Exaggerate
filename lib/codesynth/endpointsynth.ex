defmodule Exaggerate.Codesynth.Endpointsynth do
  @doc """
    master function which builds the textual material inside an endpoint file
  """
  def build_endpointmodule(swaggerfile, _filename, modulename, defs_to_ignore \\ []) do
    endpointcode = build_endpoints(swaggerfile["paths"], modulename, defs_to_ignore)
    """
      defmodule #{modulename}.Web.Endpoint do
        #{endpointcode}
      end
    """ |> Code.format_string! |> Enum.join
  end

  def build_endpoints(routelist, modulename, defs_to_ignore) when is_map(routelist) do
    routelist
      |> Enum.map(fn {route, routedef} ->
        routedef
          |> Enum.map(fn {verb, verbdef} ->
            verb |> String.to_atom
                 |> Exaggerate.Codesynth.Endpointsynth.build_endpoint(route, verbdef, modulename, defs_to_ignore)
          end)
      end)
      |> List.flatten
      |> Enum.join("\n\n")
  end

  def optional_param?(%{"required" => true}), do: false
  def optional_param?(%{}), do: true
  def optional_param?(list) do
    list |> Enum.map(&Exaggerate.Codesynth.Endpointsynth.optional_param?/1)
         |> Enum.reduce(false, &Kernel.||/2)
  end

  def optional_params(nil), do: nil
  def optional_params(list) do
    if optional_param?(list) do
      "optional_params = %{}"
    else
      ""
    end
  end

  def get_params_list(nil), do: ""
  def get_params_list(list) do
    {Exaggerate.Codesynth.Routesynth.required_params(list), optional_params(list)} |> fn
      {nil, nil} -> ""
      {nil, ""}  -> ""
      {"", ""}   -> ""
      {"", op}   -> "," <> op
      {rp, ""}   -> "," <> rp
      {rp, op}   -> "," <> rp <> "," <> op
    end.()
  end

  def get_params_comm(%{"required" => true}), do: nil
  def get_params_comm(%{"name" => name, "description" => desc}), do: "# #{name} - #{desc}"
  def get_params_comm(%{"name" => name}), do: "# #{name}"
  def get_params_comm(nil), do: ""
  def get_params_comm(list) do
    if optional_param?(list) do
      "# optional parameters: \n"
        <> (list |> Enum.map(&Exaggerate.Codesynth.Endpointsynth.get_params_comm/1)
                 |> Enum.filter(& &1)
                 |> Enum.join("\n"))
    else
      ""
    end
  end

  def build_endpoint(verb, route, route_def, _routemodule, defs_to_ignore) when is_atom(verb) and is_binary(route) and is_map(route_def) do

    methodname = route_def["operationId"]
    if methodname in defs_to_ignore do
      ""
    else
      methodargs = (if Map.has_key?(route_def, "requestBody"), do: ", requestparams", else: "") <> get_params_list(route_def["parameters"])
      param_comments = get_params_comm(route_def["parameters"])

      """
        def #{methodname}(conn#{methodargs}) do
          #{param_comments}

          # this function is autogenerated.
          # insert your code here, then delete
          # the following exception:
          raise "error: #{methodname} not implemented"

        end
      """
    end
  end
end
