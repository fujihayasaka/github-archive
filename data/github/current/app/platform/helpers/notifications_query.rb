# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class NotificationsQuery
      include Helpers::Newsies

      DATADOG_TAG_KEYS = [:statuses, :lists, :thread_types, :reasons, :owners, :authors, :exclude_owners_by_id]

      attr_accessor :viewer, :unauthorized_account_ids, :query_options

      def initialize(arguments, viewer)
        @viewer = viewer
        @unauthorized_account_ids = arguments[:unauthorized_account_ids]

        parsed_query = Search::Queries::NotificationsQuery.new(query: arguments[:query], viewer: @viewer)
        @query_options = build_query_options_from_query_parameter(parsed_query)
      end

      def count
        GitHub.newsies.web.count(viewer, query_options)
      end

      def fetch!
        GitHub.dogstats.distribution_time("newsies.graphql_fetch.time", tags: filtering_datadog_tags) do
          readable_notification_threads = all_notification_threads.map do |thread|
            thread.async_readable_by?(
              viewer,
              unauthorized_account_ids: unauthorized_account_ids,
            ).then do |readable|
              next nil unless readable
              thread
            end
          end

          Promise.all(readable_notification_threads).sync.compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end

      private

      def all_notification_threads
        timer = Timer.start
        notifications = unpack_newsies_response!(GitHub.newsies.web.all(viewer, query_options))
        timer.stop
        GitHub.dogstats.distribution("newsies.graphql_filtering.time", timer.elapsed_ms, tags: filtering_datadog_tags)

        notifications.map do |hash|
          Platform::Models::NotificationThread.new(
            hash,
            user: viewer
          )
        end
      end

      def filtering_datadog_tags
        query_options
          .to_h
          .filter { |key, value| DATADOG_TAG_KEYS.include?(key) && value.present? }
          .map { |key, _value| "#{key}:true" } + ["notifications_query:true"]
      end

      def build_query_options_from_query_parameter(parsed_query)
        query_options_hash = {
          statuses: parsed_query.statuses.map { |f| T.must(Platform::Enums::NotificationStatus.values[f.upcase]).value }.presence,
          lists: parsed_query.qualifier_used?(:repo) ? parsed_query.repositories : nil,
          thread_types: parsed_query.thread_type? ? parsed_query.thread_types : nil,
          reasons: parsed_query.qualifier_used?(:reason) ? parsed_query.reasons : nil,
          owners: parsed_query.qualifier_used?(:org) ? parsed_query.owners : nil,
          authors: parsed_query.qualifier_used?(:author) ? parsed_query.authors : nil,
          exclude_owners_by_id: unauthorized_account_ids.present? ? unauthorized_account_ids : nil,
        }.compact

        if parsed_query.client_apps_important?
          query_options_hash[:client_apps_important] = true
        elsif @viewer.feature_flag_enabled?(:issues_react_inbox_tabs, default: false)
          # If the user is using the new inbox tabs, we need to make sure we're
          # only including one possible "view:" filter in order of precedence.
          if parsed_query.focusing?
            query_options_hash[:team_mention] = nil
            query_options_hash[:not_focus_team_mentioned] = nil

            query_options_hash[:focusing] = @viewer.id
          elsif parsed_query.team_mention?
            query_options_hash[:focusing] = nil
            query_options_hash[:not_focus_team_mentioned] = nil

            query_options_hash[:team_mention] = true
          elsif parsed_query.not_focus_team_mentioned?
            query_options_hash[:focusing] = nil
            query_options_hash[:team_mention] = nil

            query_options_hash[:not_focus_team_mentioned] = @viewer.id
          end
        end

        ::Newsies::Web::FilterOptions.from(query_options_hash)
      end
    end
  end
end
