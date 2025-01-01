# typed: true
# frozen_string_literal: true
require "test_helper"

# Forcefully pull in twirp.rb to get error classes
::PackageRegistry::Twirp

module PackageRegistry
  module Twirp
    class BaseClientTest < GitHub::TestCase
      setup do
        @subject = BaseClient.new(package_registry_url: "http://packages.localhost/", package_registry_hmac_key: "myhmac")
      end

      context "#rpc" do
        test "raises error for missing twirp-class" do
          assert_raises "PackageRegistry::Twirp::BaseClient must define 'twirp_class' to return a Twirp::Client class that describes the remote service." do
            @subject.rpc("GetThings", { foo: "bar" })
          end
        end

        test "success" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          response = stub("twirp response", data: {}, error: nil)

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)

          assert_equal({}, @subject.rpc("GetThings", { foo: "bar" }))
        end

        test "not found" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          response = stub("twirp response", data: {}, error: stub(code: :not_found))
          output_class = stub("output class", new: "fake output")

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)
          twirp_class.expects(:rpcs).returns({ "GetThings" => { output_class: output_class } })

          assert_equal("fake output", @subject.rpc("GetThings", { foo: "bar" }))
        end

        test "error unavailable" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          error = stub("error", code: :unavailable, msg: "msg")
          response = stub("twirp response", data: {}, error: error)

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)

          assert_raises ::PackageRegistry::Twirp::ServiceUnavailableError do
            @subject.rpc("GetThings", { foo: "bar" })
          end
        end

        test "error already exists" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          error = stub("error", code: :already_exists, msg: "msg")
          response = stub("twirp response", data: {}, error: error)

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)

          assert_raises ::PackageRegistry::Twirp::AlreadyExistsError do
            @subject.rpc("GetThings", { foo: "bar" })
          end
        end

        test "error failed precondition" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          error = stub("error", code: :failed_precondition, msg: "msg")
          response = stub("twirp response", data: {}, error: error)

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)

          assert_raises ::PackageRegistry::Twirp::FailedPreconditionError do
            @subject.rpc("GetThings", { foo: "bar" })
          end
        end

        test "error unknown" do
          twirp_instance = mock("twirp instance")
          twirp_class = stub("twirp class", new: twirp_instance)
          error = stub("error", code: :unknown, msg: "msg")
          response = stub("twirp response", data: {}, error: error)

          @subject.stubs(:twirp_class).returns(twirp_class)
          twirp_instance.expects(:rpc).with("GetThings", { foo: "bar" }).returns(response)

          assert_raises ::PackageRegistry::Twirp::Error do
            @subject.rpc("GetThings", { foo: "bar" })
          end
        end
      end
    end
  end
end
