defmodule ExaggerateTest.Validator.ResponseTest do
  use ExUnit.Case

  alias Exaggerate.Validator
  alias Exaggerate.AST

  @basic_route """
  {
    "operationId": "root",
    "description": "gets by integer id",
    "responses": {
      "200": {
        "description": "pet response",
        "content": {
          "application/json": {
            "schema": {
              "type":"object",
              "properties":{
                "foo":{"type": "string"}
              }
            }
          }
        }
      }
    }
  }
  """

  describe "basic response filter" do
    test "correctly creates a response macro" do
      router_res = """
      if Mix.env() in [:dev, :test] do
        def root_response({:ok, resp}) do
          root_response_200_0(resp)
        end

        def root_response(_) do
          :ok
        end

        defschema root_response_200_0: \"""
                  {
                    "properties": {
                      "foo": {
                        "type": "string"
                      }
                    },
                    "type": "object"
                  }
                  \"""
      else
        def root_response(_) do
          :ok
        end
      end
      """

      assert router_res == {"/test", :post}
      |> Validator.route(Jason.decode!(@basic_route))
      |> AST.to_string
    end
  end

  @alt_code_route """
  {
    "operationId": "root",
    "description": "gets by integer id",
    "responses": {
      "201": {
        "description": "pet response",
        "content": {
          "application/json": {
            "schema": {
              "type":"object",
              "properties":{
                "foo":{"type": "string"}
              }
            }
          }
        }
      }
    }
  }
  """

  describe "response filter with alternative response code" do
    test "correctly creates a response macro" do
      router_res = """
      if Mix.env() in [:dev, :test] do
        def root_response({:ok, resp}) do
          root_response_201_0(resp)
        end

        def root_response(_) do
          :ok
        end

        defschema root_response_201_0: \"""
                  {
                    "properties": {
                      "foo": {
                        "type": "string"
                      }
                    },
                    "type": "object"
                  }
                  \"""
      else
        def root_response(_) do
          :ok
        end
      end
      """

      assert router_res == {"/test", :post}
      |> Validator.route(Jason.decode!(@alt_code_route))
      |> AST.to_string
    end
  end

  @multi_type_route """
  {
    "operationId": "root",
    "description": "gets by integer id",
    "responses": {
      "200": {
        "description": "pet response",
        "content": {
          "application/json": {
            "schema": {
              "type":"object",
              "properties":{
                "foo":{"type": "string"}
              }
            }
          },
          "image/jpeg": {
            "schema": true
          }
        }
      }
    }
  }
  """

  describe "response filter with multiple response type" do
    test "correctly creates a response macro" do
      router_res = """
      if Mix.env() in [:dev, :test] do
        def root_response({:ok, resp}) do
          resp
          |> case do
            {:file, path} ->
              {MIME.from_path(path), File.read!(resp)}
            _ ->
              {"application/json", resp}
          end
          |> case do
            {"application/json", value} -> root_response_200_0(value)
            {"image/jpeg", value} -> root_response_200_1(value)
          end
        end

        def root_response(_) do
          :ok
        end

        defschema root_response_200_0: \"""
                  {
                    "properties": {
                      "foo": {
                        "type": "string"
                      }
                    },
                    "type": "object"
                  }
                  \"""

        defschema root_response_200_1: ~s(true)

      else
        def root_response(_) do
          :ok
        end
      end
      """

      assert router_res == {"/test", :post}
      |> Validator.route(Jason.decode!(@alt_code_route))
      |> AST.to_string
    end
  end
end
