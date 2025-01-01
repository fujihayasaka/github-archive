# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class NotificationThreadSubscriptionsQuery
      include Helpers::Newsies

      attr_reader :direction, :reason, :list_type, :list_id, :unauthorized_account_ids

      MAX_PAGES = 10

      def initialize(viewer:, direction:, reason:, list_type:, list_id:, unauthorized_account_ids:)
        @viewer = viewer
        @direction = direction
        @reason = reason
        @list_type = list_type
        @list_id = list_id
        @unauthorized_account_ids = unauthorized_account_ids
      end

      def total_count
        unpack_newsies_response!(
          GitHub.newsies.count_thread_subscriptions(
            user_id: @viewer.id,
            reason: reason,
            list_type: list_type,
            list_id: list_id,
          ),
        )
      end

      # Returns a page of authorized thread subscriptions.
      #
      # Returns Newsies::PageWithPreviousAndNextFlags
      def fetch!(cursor:, limit:, direction:)
        start_time = Time.now
        num_pages = 1
        full_page = next_subscriptions_page(cursor, limit, direction)

        # Set the cursor before we filter out unauthorized data, just in case there is no authorized
        # data on the first page.
        cursor = full_page.page.last&.id

        full_page.page = authorized_subscriptions(full_page.page)

        while full_page.has_next_page && full_page.page.length < limit && num_pages < MAX_PAGES
          # We don't yet have a full page of authorized subscriptions, so keep accumulating more
          # until we run out or we've fetched a full page.

          next_page = next_subscriptions_page(cursor, limit, direction)
          next_authorized_page = authorized_subscriptions(next_page.page)
          page_gap = limit - full_page.page.length

          full_page.page += next_authorized_page.take(page_gap)
          full_page.has_next_page = next_authorized_page.length > page_gap || next_page.has_next_page
          cursor = next_page.page.last.id
          num_pages += 1
        end

        elapsed_ms = (Time.now - start_time) * 1_000
        GitHub.dogstats.timing(
          "notifications.graphql.thread_subscription_pagination",
          elapsed_ms,
          tags: ["num_pages:#{num_pages}", "page_is_full:#{full_page.page.length == limit}"])

        full_page
      end

      private

      def next_subscriptions_page(cursor, limit, direction)
        unpack_newsies_response!(
          GitHub.newsies.thread_subscriptions_by_cursor(
            user_id: @viewer.id,
            cursor: cursor,
            direction: direction,
            reason: reason,
            limit: limit,
            list_type: list_type,
            list_id: list_id,
          ),
        )
      end

      def authorized_subscriptions(subscriptions)
        readable_promises = subscriptions.map do |sub|
          sub.async_readable_by?(@viewer, unauthorized_account_ids: @unauthorized_account_ids)
        end

        async_authorized_subscriptions = Promise.all(readable_promises).then do |readable_flags|
          readable_flags
            .each_with_index
            .reduce([]) do |memo, (subscription_is_readable, index)|

            memo << subscriptions[index] if subscription_is_readable
            memo
          end
        end

        # We're forced to synchronize this in order to allow this return value to be used in a
        # while loop by the caller. Even so, using a promise to batch up to this point saves us a
        # few queries.
        async_authorized_subscriptions.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
