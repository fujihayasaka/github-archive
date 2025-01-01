# typed: true
# frozen_string_literal: true

module Notifications
  module V2
    class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include PlatformHelper

      attr_reader(
        :before,
        :after,
        :query,
        :user,
        :filters,
        :inbox_unread_count,
        :repo_notification_counts,
      )

      delegate :read?, :unread?, :archived?, :starred?, to: :query

      def initialize(attributes = nil)
        super

        raise ArgumentError, "User required" unless user

        @filters = attributes&.fetch(:filters, [])
        @inbox_unread_count = attributes&.fetch(:inbox_unread_count, 0)
        @repo_notification_counts = attributes&.fetch(:repo_notification_counts, []).presence || []
        @non_default_tabs = build_sidebar_tabs_for_filters(@filters) + build_sidebar_tabs_for_repos(@repo_notification_counts)
        @unwatch_suggestions = attributes&.fetch(:unwatch_suggestions, nil)
      end

      def previewless_notification_url(resource_url, notification_id)
        params = filter_params(before: before, after: after)

        parsed_url = Addressable::URI.parse(resource_url)
        parsed_url.query_values = (parsed_url.query_values || {}).merge({
          "notification_referrer_id" => notification_id,
          "notifications_query" => params[:query].presence,
          "notifications_before" => params[:before].presence,
          "notifications_after" => params[:after].presence,
        }.compact)
        parsed_url.to_s
      rescue Addressable::URI::InvalidURIError
        NotificationsFailbot.report("Invalid notification url for #{notification_id}")
        ""
      end

      def notifications_path(unread: unread?, read: read?, before: nil, after: nil)
        # If both are nil, use whatever their current values are,
        # but if one or the other is set use that
        if before.nil? && after.nil?
          before = self.before
          after = self.after
        end

        urls.notifications_path(filter_params(before: before, after: after, unread: unread, read: read))
      end

      def notifications_filter_path(unread: unread?, read: read?, archived: archived?, starred: starred?, repositories: selected_repositories)
        urls.notifications_path(filter_params(unread: unread, read: read, archived: archived, starred: starred, repositories: repositories))
      end

      def notifications_recent_notifications_alert_path(since:)
        params = filter_params(repositories: selected_repositories, since: since.to_i)
        urls.notifications_beta_recent_notifications_alert_path(params)
      end

      def notifications_repository_filter_path
        urls.notifications_beta_repository_filter_path(filter_params)
      end

      def notifications_tab_path(tab:)
        # Must not have a query string so that we direct properly based on user preferences
        if tab == SidebarTab::INBOX_ID
          return urls.notifications_path
        end

        urls.notifications_path(query: query_string_for_tab(tab).presence)
      end

      def query_string_for_tab(tab)
        case tab
        when SidebarTab::INBOX_ID then ""
        when SidebarTab::SAVED_ID then SidebarTab::SAVED_QUERY
        when SidebarTab::DONE_ID then SidebarTab::DONE_QUERY
        end
      end

      def selected_filter_text
        unread_only? ? "Unread" : "All"
      end

      # Returns whether or not the tab identified by the given ID is selected or not.
      # Note that multiple tabs can be selected at the same time.
      #
      # candidate_tab_id - Either one of (:inbox, :saved, :done), or the node ID of the
      #   object (either a Platform::Objects::NotificationFilter or a Platform::Objects::Repository)
      #   representing the tab.
      #
      # Returns a Boolean.
      def selected_tab?(candidate_tab_id)
        selected_tabs.any? { |t| t.id == candidate_tab_id }
      end

      def selected_item
        id = nil
        if query.is_only_an_inbox_query?
          id = "inbox"
        end
        if query.query == SidebarTab::SAVED_QUERY
          id = "saved"
        end
        if query.query == SidebarTab::DONE_QUERY
          id = "done"
        end
        id
      end

      # Returns String title of the first selected tab.
      def selected_tab_title
        selected_tabs.first&.name || query.query
      end

      # Returns a Boolean for whether or not a filter is selected in the sidebar.
      def filter_tab_selected?
        selected_tabs.any?(&:filter_tab?)
      end

      # Returns Array<SidebarTab> where each element represents one selected tab.
      def selected_tabs
        return @selected_tabs if defined?(@selected_tabs)

        @selected_tabs = []

        if query.is_only_an_inbox_query?
          @selected_tabs << SidebarTab.new(id: SidebarTab::INBOX_ID, type: SidebarTab::STATUS_TYPE, name: "Inbox", query: query.query)
        end

        if query.query == SidebarTab::SAVED_QUERY
          @selected_tabs << SidebarTab.new(id: SidebarTab::SAVED_ID, type: SidebarTab::STATUS_TYPE, name: "Saved", query: SidebarTab::SAVED_QUERY)
        end

        if query.query == SidebarTab::DONE_QUERY
          @selected_tabs << SidebarTab.new(id: SidebarTab::DONE_ID, type: SidebarTab::STATUS_TYPE, name: "Done", query: SidebarTab::DONE_QUERY)
        end

        @selected_tabs += @non_default_tabs.find_all { |t| query.query == t.query.strip }

        @selected_tabs
      end

      def query_string_for_repo(name_with_display_owner)
        "repo:#{name_with_display_owner}"
      end

      def notifications_repository_tab_path(name_with_display_owner, include_unread_filter_if_set = false)
        query_str = query_string_for_repo(name_with_display_owner)

        query_str = "#{query_str} is:unread" if include_unread_filter_if_set && unread?

        urls.notifications_path(query: query_str)
      end

      def notifications_gists_path
        query_str = "is:gist"
        query_str += " is:unread" if unread?
        urls.notifications_path(query: query_str)
      end

      def notifications_team_discussions_path
        query_str = "is:team-discussion"
        query_str += " is:unread" if unread?
        urls.notifications_path(query: query_str)
      end

      def unread_only?
        unread? && !read?
      end

      def all?
        (read? && unread?) || (!read? && !unread?)
      end

      def selected_repositories
        query.repositories
      end

      def suggestable_qualifiers
        [
          { value: "repo:", description: "filter by repository" },
          { value: "is:", description: "filter by status or discussion type" },
          { value: "reason:", description: "filter by notification reason" },
          { value: "author:", description: "filter by notification author" },
          { value: "org:", description: "filter by organization" },
        ]
      end

      # Returns the selected tab in the sidebar. If no tab is selected, returns nil.
      def selected_tab_id
        [:inbox, :saved, :done].find { |tab| selected_tab?(tab) }
      end

      # Returns a string of the filter name selected in the sidebar. If no filter is selected, returns nil.
      def selected_filter_name
        return unless filter_tab_selected?

        filters.find { |filter| selected_tab?(filter.global_relay_id) }&.name
      end

      # Returns a string of the repo name selected in the sidebar. If no repo is selected, returns nil.
      def selected_repo_name
        repo_notification_counts.take(25).find do |count|
          selected_tab?(count.repository.global_relay_id)
        end&.repository&.name
      end

      # Build list of suggestable notification reasons from the publically visible
      # NotificationReason enum values
      def suggestable_reasons
        Platform::Enums::NotificationReason.values
          .values
          .select { |enum| valid_suggestion_reason(enum) }
          .map { |enum| { value: enum.value.gsub(/_/, "-") } }
      end

      # Build list of suggestable notification thread types from the
      # NotificationsSubject union
      def suggestable_types
        # Include status filters in the list of available types. These aren't included in the
        # TYPE_QUALIFIER_MAPPINGS below because they aren't type-related, but they are also used via
        # the `is` qualifier.
        types = %w[read unread done]

        types += Search::Queries::NotificationsQuery::TYPE_QUALIFIER_MAPPINGS
          .except("issue", "pull-request", "pr")
          .keys

        # Instead of the individual types excluded above, combine Issues and PullRequests into a
        # single filter since the results are combined anyway (see
        # https://github.com/github/project-nova/issues/208#issuecomment-549538447 for discussion).
        types << "issue-or-pull-request"

        types.map { |key| { value: key } }
      end

      def show_save_custom_search?
        selected_tabs.all? do |tab|
          # Either we have a non-default inbox query ...
          (tab.id == SidebarTab::INBOX_ID && !query.is_only_an_inbox_query?) ||

          # ... or we're on a repository filter.
          tab.repository_tab?
        end
      end

      # If there a mix of read/unread/done in the query, we want to make sure they
      # are always visible, and not hidden on state-change
      def show_all_notification_states?
        (query.read? || query.unread?) && query.archived?
      end

      # If we are only showing archived notifications, make sure we hide read/unread on
      # state change
      def show_only_archived_notifications?
        !query.read? && !query.unread? && query.archived?
      end

      def show_unread_toggle?
        selected_tabs.empty? || selected_tabs.any? { |tab| tab.id == SidebarTab::INBOX_ID || tab.repository_tab? }
      end

      def can_be_grouped_by_repo?
        self.class.user_can_view_grouped_by_repo?(user, query)
      end

      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def grouped_by_list?
        @grouped_by_list ||= self.class.user_viewing_notifications_grouped_by_repo?(user, query)
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def self.user_viewing_notifications_grouped_by_repo?(user, query)
        user_can_view_grouped_by_repo?(user, query) && user.prefer_notifications_grouped_by_list?
      end

      def self.user_can_view_grouped_by_repo?(user, query)
        query.is_only_an_inbox_query?
      end

      def self.repo_notification_counts_limit(user, query)
        if user_viewing_notifications_grouped_by_repo?(user, query)
          100
        else
          25
        end
      end

      def bulk_action_job_running?(user_id)
        job_status = Newsies::MarkAllNotificationsFromQueryJobStatus.status(user_id)
        job_status && !job_status.finished?
      end

      def bulk_job_path(user_id)
        job_id = Newsies::MarkAllNotificationsFromQueryJobStatus.job_id(user_id)
        urls.job_status_path(job_id)
      end

      def protip
        [
          "Filter by <a href=\"#{notifications_filter_path(unread: true)}\" class=\"Link--inTextBlock\">is:unread</a> to see what's new.", # rubocop:disable Rails/ViewModelHTML
          "Filter by <a href=\"#{notifications_filter_path(read: true)}\" class=\"Link--inTextBlock\">is:read</a> then bulk select and mark all as <kbd>Done</kbd> to clean up your inbox.", # rubocop:disable Rails/ViewModelHTML
          "Create custom filters to quickly access your most important notifications.",
          "When viewing a notification, press <kbd>e</kbd> to mark it as Done.", # rubocop:disable Rails/ViewModelHTML
          "When viewing a notification, press <kbd>shift u</kbd> to mark it as Unread.", # rubocop:disable Rails/ViewModelHTML
          mobile_protip_text
        ].sample.html_safe # rubocop:disable Rails/OutputSafety
      end

      def web_notifications_enabled_for_user?
        GitHub.newsies.settings(user).settings_enabled_for?(:web)
      end

      def show_alert_unwatch_multiple_repositories?
        return false if @unwatch_suggestions.blank? || selected_repositories.any? || user.dismissed_unwatch_suggestions?

        @unwatch_suggestions.length > 0
      end

      def show_alert_unwatch_single_repository?
        return false if @unwatch_suggestions.blank? || selected_repositories.length != 1 || user.dismissed_unwatch_suggestions?

        repo = selected_repositories.first
        @unwatch_suggestions.any? { |suggestion| suggestion.repository_id == repo.id }
      end

      def unwatch_suggestions_metadata
        return {} if @unwatch_suggestions.blank?

        {
          algorithm_version: @unwatch_suggestions.first.algorithm_version,
          snapshot_date: @unwatch_suggestions.first.snapshot_date
        }
      end

      def mobile_protip_text
        helpers.safe_join([
          "Triage notifications on the go with GitHub Mobile for ",
          helpers.safe_link_to("iOS", urls.ios_mobile_app_store_url(campaign: "notifications-protip"), target: "_blank", class: "Link--inTextBlock"),
          " or ",
          helpers.safe_link_to("Android", urls.android_mobile_app_store_url(campaign: "notifications-protip"), target: "_blank", class: "Link--inTextBlock"),
          "."
        ])
      end

      private

      class SidebarTab
        attr_reader :id, :name, :query

        INBOX_ID = :inbox
        SAVED_ID = :saved
        DONE_ID = :done

        SAVED_QUERY = "is:saved".freeze
        DONE_QUERY = "is:done".freeze

        STATUS_TYPE = :status
        FILTER_TYPE = :filter
        REPOSITORY_TYPE = :repository

        TYPES = [STATUS_TYPE, FILTER_TYPE, REPOSITORY_TYPE]

        def initialize(id:, type:, name:, query:)
          raise ArgumentError, "invalid type: #{type}" unless TYPES.include?(type)

          @id = id
          @type = type
          @name = name
          @query = query
        end

        def filter_tab?
          @type == :filter
        end

        def repository_tab?
          @type == :repository
        end
      end

      private def build_sidebar_tabs_for_repos(repo_notification_counts)
        repo_notification_counts.map do |count|
          SidebarTab.new(
            id: count.repository.global_relay_id,
            type: SidebarTab::REPOSITORY_TYPE,
            query: query_string_for_repo(count.repository.name_with_display_owner),
            name: count.repository.name_with_display_owner,
          )
        end
      end

      private def build_sidebar_tabs_for_filters(filters)
        filters.map do |f|
          SidebarTab.new(id: f.global_relay_id, type: SidebarTab::FILTER_TYPE, name: f.name, query: f.query_string)
        end
      end

      def filter_params(unread: unread?, read: read?, archived: archived?, starred: starred?, repositories: nil, repository_names: nil, **params)
        params[:query] = query.stringify(unread: unread, read: read, archived: archived, starred: starred, repositories: repositories, repository_names: repository_names) || ""
        params
      end

      def valid_suggestion_reason(enum)
        # SAVED is a value reason to return, but should be queried using `is:saved`.
        # As such, it's explicitly filtered from the list that is displayed to users as an autocomplete suggestion.
        enum != Platform::Enums::NotificationReason.values["SAVED"] && enum != Platform::Enums::NotificationReason.values["READY_FOR_REVIEW"]
      end
    end
  end
end
