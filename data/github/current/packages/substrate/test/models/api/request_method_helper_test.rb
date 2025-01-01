# typed: false
# frozen_string_literal: true

class Api::RequestMethodHelperTest < GitHub::TestCase
  class ClassMethodsTest; include Api::App::RequestMethodHelper; end
  class InstanceMethodsTest; include Api::App::RequestMethodHelper; end
  class InstanceMethodsWithEnvTest; include Api::App::RequestMethodHelper; attr_accessor :env; end

  context "class methods" do
    test "determines if a read request when an env is passed in" do
      assert ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "GET" })
      assert ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "HEAD" })
      assert ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "OPTIONS" })
      refute ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "POST" })
      refute ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "PUT" })
      refute ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "PATCH" })
      refute ClassMethodsTest.read_request?({ "REQUEST_METHOD" => "DELETE" })
    end

    test "determines if a write request when an env is passed in" do
      refute ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "GET" })
      refute ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "HEAD" })
      refute ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "OPTIONS" })
      assert ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "POST" })
      assert ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "PUT" })
      assert ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "PATCH" })
      assert ClassMethodsTest.write_request?({ "REQUEST_METHOD" => "DELETE" })
    end
  end

  context "instance methods" do
    test "determines read when the env is passed in" do
      instance = InstanceMethodsTest.new
      assert instance.read_request?({ "REQUEST_METHOD" => "GET" })
      assert instance.read_request?({ "REQUEST_METHOD" => "HEAD" })
      assert instance.read_request?({ "REQUEST_METHOD" => "OPTIONS" })
      refute instance.read_request?({ "REQUEST_METHOD" => "POST" })
      refute instance.read_request?({ "REQUEST_METHOD" => "PUT" })
      refute instance.read_request?({ "REQUEST_METHOD" => "PATCH" })
      refute instance.read_request?({ "REQUEST_METHOD" => "DELETE" })
    end

    test "determines write when the env is passed in" do
      instance = InstanceMethodsTest.new
      refute instance.write_request?({ "REQUEST_METHOD" => "GET" })
      refute instance.write_request?({ "REQUEST_METHOD" => "HEAD" })
      refute instance.write_request?({ "REQUEST_METHOD" => "OPTIONS" })
      assert instance.write_request?({ "REQUEST_METHOD" => "POST" })
      assert instance.write_request?({ "REQUEST_METHOD" => "PUT" })
      assert instance.write_request?({ "REQUEST_METHOD" => "PATCH" })
      assert instance.write_request?({ "REQUEST_METHOD" => "DELETE" })
    end

    test "doesn't error when nothing is passed in and there is no env getter method" do
      instance = InstanceMethodsTest.new
      refute instance.read_request?
    end

    test "doesn't error when nothing is passed in and the env getter is nil" do
      instance = InstanceMethodsWithEnvTest.new
      refute instance.read_request?
    end

    test "determines read when the env is set on the instance" do
      instance = InstanceMethodsWithEnvTest.new

      instance.env = { "REQUEST_METHOD" => "GET" }
      assert instance.read_request?

      instance.env = { "REQUEST_METHOD" => "HEAD" }
      assert instance.read_request?

      instance.env = { "REQUEST_METHOD" => "OPTIONS" }
      assert instance.read_request?

      instance.env = { "REQUEST_METHOD" => "POST" }
      refute instance.read_request?

      instance.env = { "REQUEST_METHOD" => "PUT" }
      refute instance.read_request?

      instance.env = { "REQUEST_METHOD" => "PATCH" }
      refute instance.read_request?

      instance.env = { "REQUEST_METHOD" => "DELETE" }
      refute instance.read_request?
    end

    test "determines write when the env is set on the instance" do
      instance = InstanceMethodsWithEnvTest.new

      instance.env = { "REQUEST_METHOD" => "GET" }
      refute instance.write_request?

      instance.env = { "REQUEST_METHOD" => "HEAD" }
      refute instance.write_request?

      instance.env = { "REQUEST_METHOD" => "OPTIONS" }
      refute instance.write_request?

      instance.env = { "REQUEST_METHOD" => "POST" }
      assert instance.write_request?

      instance.env = { "REQUEST_METHOD" => "PUT" }
      assert instance.write_request?

      instance.env = { "REQUEST_METHOD" => "PATCH" }
      assert instance.write_request?

      instance.env = { "REQUEST_METHOD" => "DELETE" }
      assert instance.write_request?
    end
  end
end
