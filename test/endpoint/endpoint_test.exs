defmodule ExaggerateTest.EndpointTest do
  use ExUnit.Case

  @moduletag :one

  alias Exaggerate.Endpoint
  alias Exaggerate.AST

  describe "testing endpoint generating defs" do
    test "endpoint block with no parameters works" do
      blockcode_res = """
      def testblock(conn) do
        # autogen function.
        # insert your code here, then delete
        # the next exception:
        raise "error: testblock not implemented"
      end
      """

      assert blockcode_res == :testblock
      |> Endpoint.block([])
      |> AST.to_string
    end

    test "endpoint block with one parameter works" do
      blockcode_res = """
      def testblock(conn, param1) do
        # autogen function.
        # insert your code here, then delete
        # the next exception:
        raise "error: testblock not implemented"
      end
      """

      assert blockcode_res == :testblock
      |> Endpoint.block([:param1])
      |> AST.to_string
    end

    test "endpoint block with two parameters works" do
      blockcode_res = """
      def testblock(conn, param1, param2) do
        # autogen function.
        # insert your code here, then delete
        # the next exception:
        raise "error: testblock not implemented"
      end
      """

      assert blockcode_res == :testblock
      |> Endpoint.block([:param1, :param2])
      |> AST.to_string
    end
  end

  @one_def_module """
  defmodule ModuleTest.Web.Endpoint do
    def testblock1(conn) do
      # autogen function.
      # insert your code here, then delete
      # the next exception:
      raise "error: testblock1 not implemented"
    end
  end
  """

  @two_def_module """
  defmodule ModuleTest.Web.Endpoint do
    def testblock1(conn) do
      # autogen function.
      # insert your code here, then delete
      # the next exception:
      raise "error: testblock1 not implemented"
    end

    def testblock2(conn, param) do
      # autogen function.
      # insert your code here, then delete
      # the next exception:
      raise "error: testblock2 not implemented"
    end
  end
  """

  describe "testing endpoint generating modules" do
    test "endpoint module works with one def in the module" do
      assert @one_def_module == "module_test"
      |> Endpoint.module(%{testblock1: []})
      |> AST.to_string
    end

    test "endpoint module works with two defs in the module" do
      assert @two_def_module == "module_test"
      |> Endpoint.module(%{testblock1: [], testblock2: [:param]})
      |> AST.to_string
    end
  end

  def random_file do
    filename = [?0..?9, ?a..?z, ?A..?Z]
    |> Enum.concat
    |> Enum.take_random(16)
    |> List.to_string
    |> String.replace_suffix("", ".dat")
    Path.join("/tmp/", filename)
  end

  describe "features to do update" do
    test "can count implemented endpoints" do
      assert [:testblock1] == Endpoint.list(@one_def_module)
      assert [:testblock1, :testblock2] == Endpoint.list(@two_def_module)
    end

    test "can count implemented endpoints from file" do
      onedef_file = random_file
      File.write!(onedef_file, @one_def_module)
      assert [:testblock1] == Endpoint.list_file(onedef_file)

      twodef_file = random_file
      File.write!(twodef_file, @two_def_module)
      assert [:testblock1, :testblock2] == Endpoint.list_file(twodef_file)
    end
  end

end
