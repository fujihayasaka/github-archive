# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class WatchersQuery
      attr_accessor :cursor, :cursor_direction, :limit, :repository
      attr_reader :model_to_be_queried

      def initialize(repository, viewer:)
        @repository = repository
        # Tell Newsies to filter out spam unless the current viewer is a site admin
        @exclude_spammy_users = !viewer&.site_admin?
        @model_to_be_queried = ::User
      end

      def fetch!
        with_graceful_failure do
          newsies.subscriber_ids_by_cursor(repository, pagination_args)
        end
      end

      #FIXME: Ideally this could be executed at the same time as when the
      # subscriber_ids are fetched to limit the number of queries being made.
      def count
        with_graceful_failure { newsies.count_subscribers(repository, exclude_spammy_users: @exclude_spammy_users) }
      end

      private

      def with_graceful_failure(&block)
        response = block.call

        if response.failed?
          raise Platform::Errors::ServiceUnavailable.new("Watchers and watching features are currently unavailable. Please try again later.")
        else
          response
        end
      end

      def newsies
        @service ||= ::Newsies::Service.new
      end

      def pagination_args
        {
          pagination_type: :cursor,
          cursor: cursor,
          cursor_direction:  cursor_direction,
          limit: limit,
          exclude_spammy_users: @exclude_spammy_users,
        }
      end
    end
  end
end
