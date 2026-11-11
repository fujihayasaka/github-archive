# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class NotificationThreadsQuery
      include Helpers::Newsies

      DATADOG_TAG_KEYS = [:statuses, :lists, :thread_types, :reasons, :owners, :authors]

      attr_accessor :viewer, :unauthorized_account_ids, :query_options, :starred_only, :internal_request, :sort_order

      # Preload data in fetched models
      attr_reader :preload
      alias_method :preload?, :preload

      def initialize(arguments, viewer)
        @viewer = viewer
        @unauthorized_account_ids = arguments[:unauthorized_account_ids]
        @internal_request = arguments[:internal_request]
        @sort_order = arguments[:sort_order]
        @feature_flags = arguments.fetch(:feature_flags, [])
        @preload = arguments.fetch(:preload, false)

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
        measure_fetch_time do
          filter_notifications(notification_threads)
        end
      end

      private

      def measure_fetch_time(&block)
        tags = filtering_datadog_tags + ["internal:#{!!internal_request}", "starred:#{!!starred_only}"]

        GitHub.dogstats.distribution_time("newsies.graphql_fetch.time", tags: tags) do
          yield
        end
      end

      def filter_notifications(notifications)
        readable_threads = notifications.filter_map do |thread|
          # Drop repository advisory notification objects for external API calls.
          #
          # Context: https://github.com/github/github/issues/125008
          next false if thread.internal_only? && !internal_request

          # Exclude agent session threads as they lack GraphQL support. Including them causes query failures
          # because `AgentSessionThread` is not defined in the GraphQL schema.
          #
          # Remove this exclusion once GraphQL support is added.
          # See: https://github.com/github/mobile-ios/issues/23762
          next false if thread.agent_session_thread? && !internal_request

          thread.async_readable_by?(viewer, unauthorized_account_ids: unauthorized_account_ids)
            .then { |readable| thread if readable }
        end

        loaded_threads = Promise.all(readable_threads).then do |threads|
          next threads.compact unless preload?

          Promise.all(threads.compact.map(&:async_preload))
        end

        loaded_threads.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      def notification_threads
        starred_only ? saved_notification_threads : all_notification_threads
      end

      def saved_notification_threads
        unpack_newsies_response!(GitHub.newsies.web.all_saved(viewer, query_options)).map do |hash|
          Platform::Models::NotificationThread.new(hash, user: viewer, starred: true)
        end
      end

      def all_notification_threads
        notifications, saved = load_notification_entries

        notifications.map do |hash|
          Platform::Models::NotificationThread.new(
            hash,
            user: viewer,
            starred: saved[hash[:id]],
          )
        end
      end

      def load_notification_entries
        timer = Timer.start
        notifications = unpack_newsies_response!(GitHub.newsies.web.all(viewer, query_options))
        timer.stop
        GitHub.dogstats.distribution("newsies.graphql_filtering.time", timer.elapsed_ms, tags: filtering_datadog_tags)

        threads = notifications.reduce({}) do |acc, hash|
          list = ::Newsies::List.new(hash.dig(:list, :type), hash.dig(:list, :id))
          acc[hash[:id]] = ::Newsies::Thread.new(hash.dig(:thread, :type), hash.dig(:thread, :id), list: list)
          acc
        end
        saved_entries = unpack_newsies_response!(GitHub.newsies.web.all_saved_by_threads(viewer, threads.values))
        saved_keys = saved_entries.map { |entry| entry.newsies_thread.composite_key }.to_set

        saved = notifications.reduce({}) do |acc, hash|
          acc[hash[:id]] = saved_keys.member?(threads[hash[:id]]&.composite_key)
          acc
        end

        [notifications, saved]
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
          authors: parsed_query.qualifier_used?(:author) ? parsed_query.authors : nil,
          sort_order: sort_order,
        }.compact

        if unauthorized_account_ids.present? && viewer.feature_flag_enabled?(:notifications_exclude_entries_by_owner_id, default: false)
          query_options_hash[:exclude_owners_by_id] = unauthorized_account_ids
        end

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
