defmodule ExaggerateTest.RouterTest do
  use ExUnit.Case

  alias Exaggerate.Router
  alias Exaggerate.AST

  # PATHS AND OPERATIONS tests - as defined in the
  # OpenAPI documentation file:
  # https://swagger.io/docs/specification/paths-and-operations/

  describe "testing router generating simple defs" do
    test "simplest router" do
      blockcode_res = """
      get "/test" do
        with {:ok, response} <- Endpoint.test_endpoint(var!(conn)) do
          send_formatted(var!(conn), 200, response)
        else
          {:error, ecode, response} ->
            send_formatted(var!(conn), ecode, response)
        end
      end
      """

      assert blockcode_res == {"/test", :get}
      |> Router.route(%{"operationId" => "test_endpoint"})
      |> AST.to_string
    end

    test "router with summary" do
      blockcode_res = """
      get "/test" do
        # tests an endpoint
        with {:ok, response} <- Endpoint.test_endpoint(var!(conn)) do
          send_formatted(var!(conn), 200, response)
        else
          {:error, ecode, response} ->
            send_formatted(var!(conn), ecode, response)
        end
      end
      """

      assert blockcode_res == {"/test", :get}
      |> Router.route(%{"operationId" => "test_endpoint",
                        "summary" => "tests an endpoint"})
      |> AST.to_string
    end
  end
end
