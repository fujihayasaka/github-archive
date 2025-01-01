# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class AdminClient
      attr_reader :client

      # Public: Construct an AdminClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::AdminAPIClient.new(faraday_connection)
      end

      # Public: Set custom concurrent migration limit for a customer.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # customer_id - is the id of the customer. If there's a business, it's the business slug, if it's an organization, it's the organization login
      # limit - is the custom concurrent migrations limit that will be configured for customer.
      #
      # Returns an empty hash.
      def set_customer_queue_limit(customer_id:, is_business:, limit:)
        response = client.set_customer_queue_limit(customer_id: customer_id, is_business: is_business, limit: limit)

        if response.error
          raise Octoshift::Twirp::CustomerQueueNotFound if response.error.code == :not_found

          # Raise unhandled error
          raise Error, response.error
        end

        {}
      end

      # Public: Set system queue enabled state for Octoshift.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # is_enabled - indicates whether the system queue will be enabled or disabled
      #
      # Returns an empty hash.
      def set_system_queue_enabled_state(is_enabled:)
        response = client.set_system_queue_enabled_state(
          is_enabled: Google::Protobuf::BoolValue.new(value: is_enabled)
        )

        raise Error, response.error if response.error

        {}
      end
    end
  end
end
