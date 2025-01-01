# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module Newsies
      extend T::Helpers

      requires_ancestor { ::Object }

      def unpack_newsies_response!(response)
        if response.failed?
          raise Errors::ServiceUnavailable.new("Notifications features are currently unavailable.")
        end
        response.value
      end

      # As we look to move away from direct calls to `GitHub.service`
      # as outlined in our style guide:
      #
      # https://github.com/github/notifications/blob/master/docs/architecture-style-guide.md#rule-internal-must-not-use-service-api
      #
      # We still need a way to handle the errors that are raised if the mysql2
      # cluster is down. Instead of duplicating the logic from the Resiliency::Response class:
      #
      # https://github.com/github/github/blob/6d5d31d35e4b442ff0a559f339957deb41af05a2/lib/resiliency/response.rb#L8-L45.
      #
      # This method is a single isolated call to Newsies::Response. This method accepts a block which
      # will catch errors and propagate them up into graphql errors if a faliure happen on the mysql2 cluster.
      # The benefit of this method is that it allows us to call ActiveRecord directly without having to wrap each call in a
      # ::Newsies::Response call.
      #
      # Example:
      #
      # response = handle_newsies_service_unavailable do
      #   Newsies::ListSubscription.for_user(user)
      # end
      #
      def handle_newsies_service_unavailable(&block)
        unpack_newsies_response!(::Newsies::Response.new(&block))
      end
    end
  end
end
