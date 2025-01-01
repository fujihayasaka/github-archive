# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class NotificationThreadsQuery
      include Helpers::Newsies

      DATADOG_TAG_KEYS = [:statuses, :lists, :thread_types, :reasons, :owners, :authors]

      attr_accessor :viewer, :unauthorized_account_ids, :query_options, :starred_only, :internal_request

      def initialize(arguments, viewer)
        @viewer = viewer
        @unauthorized_account_ids = arguments[:unauthorized_account_ids]
        @internal_request = arguments[:internal_request]
        @feature_flags = arguments.fetch(:feature_flags, [])

        if arguments.has_key?(:query)
          parsed_query = Search::Queries::NotificationsQuery.new(query: arguments[:query], viewer: @viewer)

          @query_options = build_query_options_from_query_parameter(parsed_query)
          @starred_only = parsed_query.starred?
        else
          @query_options = build_query_options_from_filter_by_parameters(arguments[:filter_by])
          @starred_only = arguments[:filter_by][:starred_only] || arguments[:filter_by][:saved_only] if arguments[:filter_by]
        end
      end

      def count
        if starred_only
          GitHub.newsies.web.count_saved(viewer, query_options)
        else
          GitHub.newsies.web.count(viewer, query_options)
        end
      end

      def fetch!
        tags = filtering_datadog_tags + ["internal:#{!!internal_request}", "starred:#{!!starred_only}"]
        GitHub.dogstats.distribution_time("newsies.graphql_fetch.time", tags: tags) do
          notification_threads = if starred_only
            saved_notification_threads
          else
            all_notification_threads
          end

          readable_notification_threads = notification_threads.map do |thread|
            # Drop repository advisory notification objects for external API calls.
            #
            # Context: https://github.com/github/github/issues/125008
            unless internal_request
              next if thread.thread_type == "RepositoryAdvisory"
              next if thread.thread_type == "AdvisoryCredit"
            end

            thread.async_readable_by?(
              viewer,
              unauthorized_account_ids: unauthorized_account_ids,
            ).then do |readable|
              next nil unless readable
              thread
            end
          end

          Promise.all(readable_notification_threads).sync.compact
        end
      end

      private

      def saved_notification_threads
        unpack_newsies_response!(GitHub.newsies.web.all_saved(viewer, query_options)).map do |hash|
          Platform::Models::NotificationThread.new(hash, user: viewer, starred: true)
        end
      end

      def all_notification_threads
        timer = Timer.start
        notifications = unpack_newsies_response!(GitHub.newsies.web.all(viewer, query_options))
        timer.stop
        GitHub.dogstats.distribution("newsies.graphql_filtering.time", timer.elapsed_ms, tags: filtering_datadog_tags)

        summary_ids = notifications.map { |hash| hash[:id] }
        saved_summary_ids = unpack_newsies_response!(GitHub.newsies.web.all_saved_by_summary_ids(viewer, summary_ids))

        notifications.map do |hash|
          Platform::Models::NotificationThread.new(
            hash,
            user: viewer,
            starred: saved_summary_ids.include?(hash[:id].to_i),
          )
        end
      end

      def filtering_datadog_tags
        query_options
          .to_h
          .filter { |key, value| DATADOG_TAG_KEYS.include?(key) && value.present? }
          .map { |key, _value| "#{key}:true" }
      end

      def build_query_options_from_query_parameter(parsed_query)
        query_options_hash = {
          statuses: parsed_query.statuses.map { |f| T.must(Platform::Enums::NotificationStatus.values[f.upcase]).value }.presence,
          lists: parsed_query.qualifier_used?(:repo) ? parsed_query.repositories : nil,
          thread_types: parsed_query.thread_type? ? parsed_query.thread_types : nil,
          reasons: parsed_query.qualifier_used?(:reason) ? parsed_query.reasons : nil,
          owners: parsed_query.qualifier_used?(:org) ? parsed_query.owners : nil,
          authors: parsed_query.qualifier_used?(:author) ? parsed_query.authors : nil
        }.compact

        if parsed_query.client_apps_important?
          query_options_hash[:client_apps_important] = true
        elsif @viewer.feature_enabled?(:issues_react_inbox_tabs)
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

      def build_query_options_from_filter_by_parameters(filter_by)
        return {} unless filter_by.present?

        query_options_hash = {}
        query_options_hash[:statuses] = filter_by[:statuses]
        query_options_hash[:reasons] = filter_by[:reasons]
        query_options_hash[:lists] = list_ids_to_active_record_objects(filter_by[:list_ids]) if filter_by[:list_ids]
        query_options_hash[:thread_types] = filter_by[:thread_types] if filter_by[:thread_types]

        ::Newsies::Web::FilterOptions.from(query_options_hash)
      end

      def list_ids_to_active_record_objects(lists)
        list_database_ids_by_type = lists.reduce({}) do |memo, list_global_relay_id|
          type, database_id = Platform::Helpers::NodeIdentification.from_global_id(list_global_relay_id)
          memo[type] ||= []
          memo[type] << database_id
          memo
        end

        list_database_ids_by_type
          .map { |type, ids| type.safe_constantize&.where(id: ids)&.all || [] }
          .flatten
      end
    end
  end
end
