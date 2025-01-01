# typed: true
# frozen_string_literal: true
require "test_helper"

class Api::Internal::EnforcerTest < GitHub::TestCase
  include PlatformTestHelpers::InterfaceHelpers

  # for these tests the return type is not important, but rather that the enforcer returns the expected values
  ORIGIN_ERR_MSG = "ConditionalAccess::Api::Internal::Enforcer must be called from an internal origin only, but received origin: public"
  IP_ERR_MSG = "actor ip was missing in GraphQL context"
  MISSING_GQL_QUERY_MSG = "Internal GraphQL call without query in context"
  USER = 1
  WEB_SESSION = 2

  setup do
    @mocked_request = RequestMock.new

    @context = { origin: Platform::ORIGIN_INTERNAL, rails_request: @mocked_request, viewer: USER, user_session: WEB_SESSION }
    @graphql_query_mock = Struct.new(:query?)
  end

  context "actor" do
    test "raises for non internal origins" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: "public" })
      e = assert_raises Platform::Errors::Execution do
        enforcer.actor
      end
      assert_equal ORIGIN_ERR_MSG, e.message
    end

    test "returns viewer as actor" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_equal USER, enforcer.actor
    end
  end

  context "actor_ip" do
    test "raises for non internal origins" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: "public" })
      e = assert_raises Platform::Errors::Execution do
        enforcer.actor_ip
      end
      assert_equal ORIGIN_ERR_MSG, e.message
    end

    test "raises for missing ip attribute" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: Platform::ORIGIN_INTERNAL })
      e = assert_raises Platform::Errors::Execution do
        enforcer.actor_ip
      end
      assert_equal IP_ERR_MSG, e.message
    end

    test "returns rails request remote_ip as actor_ip" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_equal "4.3.2.1", enforcer.actor_ip
    end
  end

  context "web_session" do
    test "raises for non internal origins" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: "public" })
      e = assert_raises Platform::Errors::Execution do
        enforcer.web_session
      end
      assert_equal ORIGIN_ERR_MSG, e.message
    end

    test "returns nil if session is not present" do
      context = { origin: Platform::ORIGIN_INTERNAL, rails_request: @mocked_request, viewer: USER }
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(context)
      assert_nil enforcer.web_session
    end

    test "returns session if present" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_equal WEB_SESSION, enforcer.web_session
    end
  end

  context "anonymous?" do
    test "raises for non internal origins" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: "public" })
      e = assert_raises Platform::Errors::Execution do
        enforcer.anonymous?
      end
      assert_equal ORIGIN_ERR_MSG, e.message
    end

    test "false if there is an actor" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      refute enforcer.anonymous?
    end

    test "true if there is no actor" do
      context = { origin: Platform::ORIGIN_INTERNAL, rails_request: @mocked_request }
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(context)
      assert enforcer.anonymous?
    end
  end

  context "safe_request_method?" do
    test "raises for non internal origins" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: "public" })
      e = assert_raises Platform::Errors::Execution do
        enforcer.safe_request_method?
      end
      assert_equal ORIGIN_ERR_MSG, e.message
    end

    test "raises for missing graphql query" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new({ origin: Platform::ORIGIN_INTERNAL })
      e = assert_raises Platform::Errors::Execution do
        enforcer.safe_request_method?
      end
      assert_equal MISSING_GQL_QUERY_MSG, e.message
    end

    test "returns true if request is graphql query" do
      @context.stubs(:query).returns(@graphql_query_mock.new(true))
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert enforcer.safe_request_method?
    end
  end

  context "location" do
    test "returns api as location" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_equal :internal_api, enforcer.location
    end
  end

  context "conditional access policies" do
    test "lists conditional access policies" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_same_elements ConditionalAccess::Api::Internal::Enforcer::DEFAULT_POLICIES, enforcer.conditional_access_policies
    end
  end

  context "registered policies" do
    test "lists registered policies" do
      enforcer = ConditionalAccess::Api::Internal::Enforcer.new(@context)
      assert_same_elements ConditionalAccess::Api::Internal::Enforcer::DEFAULT_POLICIES, enforcer.registered_policies
    end
  end
end
