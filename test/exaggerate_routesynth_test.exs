
defmodule Codesynth.Helper do
  defmacro codesynth_match(map, code, verb, path) do
    quote do
      get_route = unquote(map)
      get_code = unquote(code) |> String.trim_trailing |> Code.format_string! |> Enum.join

      #IO.puts("======")
      #IO.puts Exaggerate.Codesynth.build_route(unquote(verb), unquote(path), get_route)
      #IO.puts("------")
      #IO.puts get_code
      #IO.puts("------")

      assert Exaggerate.Codesynth.Routesynth.build_route(unquote(verb), unquote(path), get_route, "TestModule") == get_code
    end
  end
end


defmodule ExaggerateCodesynthUnitTest do
  use ExUnit.Case
  doctest Exaggerate.Codesynth.Routesynth
  #some of these things can't be put into doctests because of too many quotation
  #marks which seems to confuse the compiler.

  test "get_params_list" do
    assert Exaggerate.Codesynth.Routesynth.get_params_list([%{"required" => false, "name" => "test"}]) == ",%{\"test\" => test}"
    assert Exaggerate.Codesynth.Routesynth.get_params_list([%{"required" => false, "name" => "test1"}, %{"required" => false, "name" => "test2"}]) == ",%{\"test1\" => test1,\"test2\" => test2}"
    assert Exaggerate.Codesynth.Routesynth.get_params_list([%{"required" => true, "name" => "test1"}, %{"required" => false, "name" => "test2"}]) == ",test1,%{\"test2\" => test2}"
  end
end

defmodule ExaggerateCodesynthIntegrationTest do
  import Codesynth.Helper
  use ExUnit.Case

  #test "build route requirements" do
  #  get_route = %{"responses" => %{"default" => "success"}}
  #  refute Exaggerate.Paths.Item.Get.is_valid?(get_route)
  #  assert_raise RuntimeError, "Exaggerate requires operationIds for all routes.", Exaggerate.Codesynth.build_route(:get, "/barebones", get_route)

  #  get_route = %{"operationId" => "barebones"}
  #  refute Exaggerate.Paths.Item.Get.is_valid?(get_route)
  #  assert_raise RuntimeError, "Exaggerate requires response for all routes.", Exaggerate.Codesynth.build_route(:get, "/barebones", get_route)
  #end

  test "bare bones get" do

    codesynth_match(
      %{"operationId" => "barebones",
      "responses" => %{"default" => "success"}},
      """
      get "/barebones" do
        case TestModule.barebones(conn) do
          _ -> send_formatted(conn, 200, "success")
        end
      end
      """,
      :get, "/barebones")

    codesynth_match(
      %{"operationId" => "barebones",
      "responses" => %{}},
      """
      get "/barebones" do
        case TestModule.barebones(conn) do
          {:ok, content} -> send_formatted(conn, 200, content)
          _ -> send_resp(conn, 400, "")
        end
      end
      """,
      :get, "/barebones")

  end

  test "get with basic 404 error response" do

    codesynth_match(
      %{"operationId" => "e404",
      "responses" => %{"404" => %{"description" => "404 error"}}},
      """
      get "/e404" do
        case TestModule.e404(conn) do
          {:error, 404, details} -> send_formatted(conn, 404, %{"404" => "404 error:" <> details})
          {:ok, content} -> send_formatted(conn, 200, content)
          _ -> send_resp(conn, 400, "")
        end
      end
      """,
      :get, "/e404")
  end

  test "get with basic 200 success override" do

    codesynth_match(
      %{"operationId" => "b200",
      "responses" => %{"200" => %{"description" => "general success"}}},
      """
      get "/e404" do
        case TestModule.e404(conn) do
          {:ok, 200, details} -> send_formatted(conn, 200, %{"200" => "general success:" <> details})
          _ -> send_resp(conn, 400, "")
        end
      end
      """,
      :get, "/e404")
  end

  test "get with basic 201 success response" do

    codesynth_match(
      %{"operationId" => "b201",
      "responses" => %{"201" => %{"description" => "resource created"}}},
      """
      get "/b201" do
        case TestModule.b201(conn) do
          {:ok, 201, details} -> send_formatted(conn, 201, %{"201" => "resource created:" <> details})
          {:ok, content} -> send_formatted(conn, 200, content)
          _ -> send_resp(conn, 400, "")
        end
      end
      """,
      :get, "/b201")
  end

  test "get with complex 404 error response" do

    codesynth_match(
    %{"operationId" => "e404",
      "responses" => %{"404" => %{"content" =>
                                  %{"application/json" =>
                                    %{"schema" =>
                                      %{"$ref" => "#/components/schemas/Pet"}}},
                                  "description" => "can't find the file"}}},
    """
    get "/e404" do
      case TestModule.e404(conn) do
        # handles the can't find file error.
        {:error, 404, details} ->
          send_formatted(conn, 404, "can't find the file:" <> details)

        {:ok, content} ->
          send_formatted(conn, 200, content)

        _ ->
          send_resp(conn, 400, "")
      end
    end
    """,
    :get, "/e404")
  end

  ##############################################################################
  ## parameters testing

  test "get_with_one_parameter" do
    codesynth_match(
      %{"operationId" => "oneparam",
      "parameters" => [%{"name" => "param1", "in" => "header", "required" => true}],
      "responses" => %{"default" => "success"}},
      """
      get "/oneparam" do
        with {:ok, param1} <- header_parameter(conn, "param1", :required) do
          case TestModule.oneparam(conn, param1) do
            _ -> send_formatted(conn, 200, "success")
          end
        else
          {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
        end
      end
      """,
      :get, "/oneparam")
  end

  test "get_with_one_path_parameter" do
    codesynth_match(
      %{"operationId" => "oneparam",
      "parameters" => [%{"name" => "param1", "in" => "path", "required" => true}],
      "responses" => %{"default" => "success"}},
      """
      get "/oneparam/:param1" do
        case TestModule.oneparam(conn, param1) do
          _ -> send_formatted(conn, 200, "success")
        end
      end
      """,
      :get, "/oneparam/{param1}")
  end

  test "get_with_one_query_parameter" do
    codesynth_match(
      %{"operationId" => "oneparam",
      "parameters" => [%{"name" => "param1", "in" => "query", "required" => true}],
      "responses" => %{"default" => "success"}},
      """
      get "/oneparam" do
        with {:ok, param1} <- query_parameter(conn, "param1", :required) do
          case TestModule.oneparam(conn, param1) do
            _ -> send_formatted(conn, 200, "success")
          end
        else
          {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
        end
      end
      """,
      :get, "/oneparam")
  end

  test "get_with_path_and_query_parameter" do
    codesynth_match(
      %{"operationId" => "mixparam",
      "parameters" => [%{"name" => "param1", "in" => "path", "required" => true},
                       %{"name" => "param2", "in" => "query", "required" => true}],
      "responses" => %{"default" => "success"}},
      """
      get "/mixparam/:param1" do
        with {:ok, param2} <- query_parameter(conn, "param2", :required) do
          case TestModule.mixparam(conn, param1, param2) do
            _ -> send_formatted(conn, 200, "success")
          end
        else
          {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
        end
      end
      """,
      :get, "/mixparam/{param1}")
  end

  test "get_with_two_parameters" do
    codesynth_match(
      %{"operationId" => "twoparam",
        "parameters" => [%{"name" => "param1", "in" => "header", "required" => true},
                         %{"name" => "param2", "in" => "header", "required" => true}],
        "responses" => %{"default" => "success"}},
      """
      get "/twoparam" do
        with {:ok, param1} <- header_parameter(conn, "param1", :required),
             {:ok, param2} <- header_parameter(conn, "param2", :required)
        do
          case TestModule.twoparam(conn, param1, param2) do
            _ -> send_formatted(conn, 200, "success")
          end
        else
          {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
        end
      end
      """,
      :get, "/twoparam")
  end

  test "get_with_one_optional_parameter" do
    codesynth_match(
      %{"operationId" => "optparam",
        "parameters" => [%{"name" => "param1", "in" => "header"}],
        "responses" => %{"default" => "success"}},
      """
      get "/optparam" do
        param1 = header_parameter(conn, "param1")

        case TestModule.optparam(conn, %{"param1" => param1}) do
          _ -> send_formatted(conn, 200, "success")
        end
      end
      """,
      :get, "/optparam")
  end

  test "get_with_two_optional_parameters" do
    codesynth_match(
    %{"operationId" => "twoparam",
      "parameters" => [%{"name" => "param1", "in" => "header"},
                       %{"name" => "param2", "in" => "header"}],
      "responses" => %{"default" => "success"}},
    """
    get "/twoparam" do
      param1 = header_parameter(conn, "param1")
      param2 = header_parameter(conn, "param2")

      case TestModule.twoparam(conn, %{"param1" => param1, "param2" => param2}) do
        _ -> send_formatted(conn, 200, "success")
      end
    end
    """,
    :get, "/twoparam")
  end

  test "get_with_mixed_parameters" do
    codesynth_match(
    %{"operationId" => "mixparam",
      "parameters" => [%{"name" => "param1", "in" => "header", "required" => true},
                       %{"name" => "param2", "in" => "header"}],
      "responses" => %{"default" => "success"}},
    """
    get "/mixparam" do
      with {:ok, param1} <- header_parameter(conn, "param1", :required)
      do
        param2 = header_parameter(conn, "param2")

        case TestModule.mixparam(conn, param1, %{"param2" => param2}) do
          _ -> send_formatted(conn, 200, "success")
        end
      else
        {:error, parameter, problem} -> send_formatted(conn, 400, %{"400" => "error \#{problem} in parameter \#{parameter}"})
      end
    end
    """,
    :get, "/mixparam")
  end

end


defmodule ExaggeratePetshopCodesynthTest do
  import Codesynth.Helper
  use ExUnit.Case

  test "pet shop get code gets generated" do
    codesynth_match(
      %{"description" => "",
        "operationId" => "logoutUser",
        "parameters" => [],
        "produces" => ["application/xml", "application/json"],
        "responses" => %{"default" => %{"description" => "successful operation"}},
        "summary" => "Logs out current logged in user session",
        "tags" => ["user"]},
      """
      get "/user/logout" do
        # Logs out current logged in user session

        case TestModule.logoutUser(conn) do
          _ -> send_formatted(conn, 200, %{"description" => "successful operation"})
        end
      end
      """,
      :get, "/user/logout")
  end
end
