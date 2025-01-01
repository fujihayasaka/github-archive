# typed: true
# frozen_string_literal: true

require "test_helper"

module ContainerRegistry
  module Twirp
    class ContainerRegistryClientTest < GitHub::TestCase
      setup do
        @subject = ContainerRegistryClient.new(container_registry_url: "http://packages.localhost/")
      end

      context "request" do
        test "raises container-registry error when connection times out" do
          conn = GitHub::FaradayClient::External.new(url: "http://packages.localhost/") { |c| c.adapter :test, Faraday::Adapter::Test::Stubs.new }
          subject = ContainerRegistryClient.new(container_registry_url: "http://packages.localhost/", connection: conn)
          conn.expects(:get).with("/internal/namespace/blobs/digest", {}).raises(Faraday::TimeoutError.new("Connection timed out"))
          subject.expects(:failbot_report).with(is_a(Faraday::TimeoutError))
          assert_raises(ContainerRegistry::Twirp::Error) do
            subject.request(:get, "/internal/namespace/blobs/digest")
          end
        end

        test "raises container-registry service unavailable error when connection fails" do
          conn = GitHub::FaradayClient::External.new(url: "http://packages.localhost/") { |c| c.adapter :test, Faraday::Adapter::Test::Stubs.new }
          subject = ContainerRegistryClient.new(container_registry_url: "http://packages.localhost/", connection: conn)
          conn.expects(:get).with("/internal/namespace/blobs/digest", {}).raises(Faraday::ConnectionFailed.new("Connection failed"))
          subject.expects(:failbot_report).with(is_a(Faraday::ConnectionFailed))
          assert_raises(ContainerRegistry::Twirp::ServiceUnavailableError) do
            subject.request(:get, "/internal/namespace/blobs/digest")
          end
        end

      end

      context "get_blob" do
        test "returns the blob" do
          @subject.expects(:request).with(:get, "/internal/namespace/blobs/digest").returns("blob")
          blob = @subject.get_blob(namespace: "namespace", digest: "digest")
          assert_equal "blob", blob
        end

        test "returns nil when connection fails" do
          @subject.expects(:request).with(:get, "/internal/namespace/blobs/digest").raises(ContainerRegistry::Twirp::Error)
          blob = @subject.get_blob(namespace: "namespace", digest: "digest")
          assert_nil blob
        end

        test "returns nil when connection times out" do
          @subject.expects(:request).with(:get, "/internal/namespace/blobs/digest").raises(ContainerRegistry::Twirp::ServiceUnavailableError)
          blob = @subject.get_blob(namespace: "namespace", digest: "digest")
          assert_nil blob
        end

        test "returns nil when error is raised" do
          @subject.expects(:request).with(:get, "/internal/namespace/blobs/digest").raises(ContainerRegistry::Twirp::Error)
          blob = @subject.get_blob(namespace: "namespace", digest: "digest")
          assert_nil blob
        end
      end
    end
  end
end
