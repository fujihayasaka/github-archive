# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module MergeBox
      class ProtocolSelectorTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "wiseguy")
          @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
        end

        test "returns the correct protocols and values when both are available" do
          Repository.any_instance.stubs(:ssh_certificate_requirement_enabled?).returns(false)
          Repository.any_instance.stubs(:ssh_enabled?).returns(true)

          selector = ProtocolSelector.new(repository: @source, user: @owner)
          protocols = selector.protocols.index_by(&:to_sym)
          ssh = protocols.fetch(:ssh)
          http = protocols.fetch(:http)

          assert ssh.available?
          refute ssh.is_default
          assert_equal  "/users/set_protocol?protocol_selector=ssh&protocol_type=push", ssh.sticky_url
          assert_equal @source.ssh_url, ssh.url
          assert_equal :ssh, ssh.to_sym

          assert http.available?
          assert http.is_default
          assert_equal "/users/set_protocol?protocol_selector=http&protocol_type=push", http.sticky_url
          assert_equal @source.http_url, http.url
          assert_equal :http, http.to_sym
        end

        test "returns the correct default protocol if one is set" do
          Repository.any_instance.stubs(:ssh_certificate_requirement_enabled?).returns(false)
          Repository.any_instance.stubs(:ssh_enabled?).returns(true)
          GitHub::RepositoryProtocolSelector.any_instance.stubs(:push_protocol).returns(:ssh)

          selector = ProtocolSelector.new(repository: @source, user: @owner)
          protocols = selector.protocols.index_by(&:to_sym)
          ssh = protocols.fetch(:ssh)
          http = protocols.fetch(:http)

          assert ssh.available?
          assert ssh.is_default
          assert_equal  "/users/set_protocol?protocol_selector=ssh&protocol_type=push", ssh.sticky_url
          assert_equal @source.ssh_url, ssh.url
          assert_equal :ssh, ssh.to_sym

          assert http.available?
          refute http.is_default
          assert_equal "/users/set_protocol?protocol_selector=http&protocol_type=push", http.sticky_url
          assert_equal @source.http_url, http.url
          assert_equal :http, http.to_sym
        end

        test "returns the first available protocol if the selected one is not allowed - ssh not allowed" do
          Repository.any_instance.stubs(:ssh_certificate_requirement_enabled?).returns(false)
          Repository.any_instance.stubs(:ssh_enabled?).returns(false)
          GitHub::RepositoryProtocolSelector.any_instance.stubs(:push_protocol).returns(:ssh)

          selector = ProtocolSelector.new(repository: @source, user: @owner)
          protocols = selector.protocols.index_by(&:to_sym)
          ssh = protocols.fetch(:ssh)
          http = protocols.fetch(:http)

          refute ssh.available?
          refute ssh.is_default
          assert_equal  "/users/set_protocol?protocol_selector=ssh&protocol_type=push", ssh.sticky_url
          assert_equal @source.ssh_url, ssh.url
          assert_equal :ssh, ssh.to_sym

          assert http.available?
          assert http.is_default
          assert_equal "/users/set_protocol?protocol_selector=http&protocol_type=push", http.sticky_url
          assert_equal @source.http_url, http.url
          assert_equal :http, http.to_sym
        end

        test "returns the correct protocols and values when only ssh is available" do
          Repository.any_instance.stubs(:ssh_certificate_requirement_enabled?).returns(true)
          Repository.any_instance.stubs(:ssh_enabled?).returns(true)
          GitHub::RepositoryProtocolSelector.any_instance.stubs(:push_protocol).returns(:http)

          selector = ProtocolSelector.new(repository: @source, user: @owner)
          protocols = selector.protocols.index_by(&:to_sym)
          ssh = protocols.fetch(:ssh)
          http = protocols.fetch(:http)

          assert ssh.available?
          assert ssh.is_default
          assert_equal  "/users/set_protocol?protocol_selector=ssh&protocol_type=push", ssh.sticky_url
          assert_equal @source.ssh_url, ssh.url
          assert_equal :ssh, ssh.to_sym

          refute http.available?
          refute http.is_default
          assert_equal "/users/set_protocol?protocol_selector=http&protocol_type=push", http.sticky_url
          assert_equal @source.http_url, http.url
          assert_equal :http, http.to_sym
        end

        test "returns the correct protocols and values when only http is available" do
          Repository.any_instance.stubs(:ssh_certificate_requirement_enabled?).returns(false)
          Repository.any_instance.stubs(:ssh_enabled?).returns(false)

          selector = ProtocolSelector.new(repository: @source, user: @owner)
          protocols = selector.protocols.index_by(&:to_sym)
          ssh = protocols.fetch(:ssh)
          http = protocols.fetch(:http)

          refute ssh.available?
          refute ssh.is_default
          assert_equal  "/users/set_protocol?protocol_selector=ssh&protocol_type=push", ssh.sticky_url
          assert_equal @source.ssh_url, ssh.url
          assert_equal :ssh, ssh.to_sym

          assert http.available?
          assert http.is_default
          assert_equal "/users/set_protocol?protocol_selector=http&protocol_type=push", http.sticky_url
          assert_equal @source.http_url, http.url
          assert_equal :http, http.to_sym
        end
      end
    end
  end
end
