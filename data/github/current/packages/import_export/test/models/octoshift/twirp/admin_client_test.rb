# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class AdminClientTest < GitHub::TestCase
      fixtures do
        @owner_id = Faker::Number.number(digits: 6)
        @limit = 5
        @is_enabled = false
      end

      context "set_customer_queue_limit" do
        test "returns an empty hash" do
          data = MonolithTwirp::Octoshift::Migrations::V1::SetCustomerQueueLimitRequest.new
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient
            .any_instance
            .stubs(:set_customer_queue_limit)
            .with(customer_id: @owner_id, is_business: false, limit: @limit)
            .returns(twirp_client_response)

          client = Octoshift::Twirp::AdminClient.new
          response = client.set_customer_queue_limit(customer_id: @owner_id, is_business: false, limit: @limit)

          assert_instance_of Hash, response
          assert_empty response
        end

        test "raises Octoshift::Twirp::CustomerQueueNotFound when Octoshift cannot find customer queue" do
          twirp_error = ::Twirp::Error.not_found("customer queue not found", {})
          MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient
            .any_instance
            .stubs(:set_customer_queue_limit)
            .with(customer_id: @owner_id, is_business: false, limit: @limit)
            .returns(stub(error: twirp_error))

          client = Octoshift::Twirp::AdminClient.new

          assert_raises(Octoshift::Twirp::CustomerQueueNotFound) do
            client.set_customer_queue_limit(customer_id: @owner_id, is_business: false, limit: @limit)
          end
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with unhandled ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient
            .any_instance
            .stubs(:set_customer_queue_limit)
            .with(customer_id: @owner_id, is_business: false, limit: @limit)
            .returns(stub(error: twirp_error))

          client = Octoshift::Twirp::AdminClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.set_customer_queue_limit(customer_id: @owner_id, is_business: false, limit: @limit)
          end
        end
      end

      context "set_system_queue_enabled_state" do
        test "returns an empty hash" do
          data = MonolithTwirp::Octoshift::Migrations::V1::SetSystemQueueEnabledStateRequest.new
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient
            .any_instance
            .stubs(:set_system_queue_enabled_state)
            .with(is_enabled: Google::Protobuf::BoolValue.new(value: @is_enabled))
            .returns(twirp_client_response)

          client = Octoshift::Twirp::AdminClient.new
          response = client.set_system_queue_enabled_state(is_enabled: @is_enabled)

          assert_instance_of Hash, response
          assert_empty response
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with unhandled ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient
            .any_instance
            .stubs(:set_system_queue_enabled_state)
            .with(is_enabled: Google::Protobuf::BoolValue.new(value: @is_enabled))
            .returns(stub(error: twirp_error))

          client = Octoshift::Twirp::AdminClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.set_system_queue_enabled_state(is_enabled: @is_enabled)
          end
        end
      end
    end
  end
end
