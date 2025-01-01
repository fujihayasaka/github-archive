# typed: true
# frozen_string_literal: true

module ControllerMethods
  module PullRequests
    extend ActiveSupport::Concern
    extend T::Helpers

    include RelayHelper
    include ::PullRequests::MergeboxHelper
    include ::PullRequests::NewFilesChangedHelper

    requires_ancestor { ApplicationController }

    SHOW_ACTION_NAMES = [:show, :issue_layout, :issue_conversation_content].freeze

    included do
      T.bind(self, T.class_of(ApplicationController))
      helper_method :tab_specified?
      helper_method :specified_tab
      helper_method :stats
    end

    def tab_specified?(tab_name)
      specified_tab.to_s == tab_name.to_s
    end

    def params_or_default_query_string
      params[:q] || "is:pr is:open "
    end

    def default_search_tags
      %W[controller:#{controller_name} action:#{action_name} spammy:#{current_user&.spammy?} has_issues:#{current_repository&.has_issues?} logged_in:#{logged_in?}]
    end

    def parsed_issues_query=(value)
      @parsed_issues_query = value
    end

    def parsed_issues_query # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @parsed_issues_query ||= Search::Queries::IssueQuery.normalize(
        Search::Queries::IssueQuery.parse(params_or_default_query_string, current_user)
      )
    end

    def track_execution_time(method)
      is_empty_issue = !!@current_issue && !@current_issue.has_timeline_items?
      tags = ["#{GitHub::TaggingHelper::EMPTY_ISSUE_TAG}:#{is_empty_issue}", "method:#{method}"]

      track_time(tags: tags) do
        yield
      end
    end

    def should_load_participants?
      # Loads participants only in the cases really needed.
      partial ||= params[:partial]
      (action_name.present? && SHOW_ACTION_NAMES.include?(action_name.to_sym)) ||
        (action_name == "show_partial" && partial == "issues/sidebar/assignees_menu_content")
    end

    def use_strict_loading
      !action_name.nil? && SHOW_ACTION_NAMES.include?(action_name.to_sym)
    end

    def current_issue
      return @current_issue if defined?(@current_issue)

      # if there is no `id` set from the route, then we can't load the issue.
      issue_number = params[:id].to_i
      return @current_issue = nil if issue_number.zero?

      load_participants = should_load_participants?

      track_execution_time("current_issue") do
        issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
        includes = if use_strict_loading
          [
            :labels,
            :milestone,
            :pinned_issue,
            pull_request: [:user],
          ]
        else
          [:labels]
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          @current_issue = issues.includes(*includes).find_by_number(issue_number).tap do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            # Loads the participant data if it hasn't been loaded already. We load max of {Issue::VIEW_PARTICIPANT_LOAD_LIMIT},
            # since we limit the number of user profiles that are displayed on the show page and don't need to load them all into memory.
            # reverting the issue: https://github.com/github/github/pull/158345
            if load_participants
              with_database_error_fallback do
                GitHub.dogstats.time("issue.participants", tags: %W[logged_in:#{logged_in?}]) do
                  issue&.participants(user_limit: Issue::VIEW_PARTICIPANT_LOAD_LIMIT)
                end
              end
            end
          end
        end
      end
    end

    def query_parsed_search_tags
      search_tags = default_search_tags

      # is default query: query run on the /pulls or /issues page without any additional interaction
      is_default_query = false

      # when includes :assignee for the current user of @me
      is_self_assigned = false

      # when includes :author for the current user of @me
      is_self_authored = false

      # when is a exclusive issue search
      issues_only = false

      unless parsed_issues_query.nil?
        is_issue_search = parsed_issues_query.include?([:is, "issue"])
        is_pr_search = parsed_issues_query.include?([:is, "pr"])
        is_default_query = ::Search::Queries::IssueQuery.is_default_issues_index_query?(parsed_issues_query)

        issues_only = is_issue_search && !is_pr_search

        if logged_in?
          is_self_assigned = parsed_issues_query.include?([:assignee, T.must(current_user).display_login]) || parsed_issues_query.include?([:assignee, "@me"])
          is_self_authored = parsed_issues_query.include?([:author, T.must(current_user).display_login]) || parsed_issues_query.include?([:author, "@me"])
        end
      end

      # parsed_issues_query is currently an array of pairs, or a flat search query text.
      # We want to extract the filter symbols used.
      parsed_query_keys = []
      parsed_issues_query.each do |item|
        if item.is_a?(Array) && item.length == 2
          parsed_query_keys.append(item.first)
        end
      end

      PullRequestsController::PULL_REQUEST_INDEX_TAG_FILTER_SYMBOLS.each do |filter|
        filter_s = filter.to_s

        has_filter = parsed_issues_query.include?([:no, filter_s]) ||
          parsed_query_keys.include?(filter) ||
          parsed_issues_query.include?([:is, filter_s])

        search_tags.append("has_#{filter_s}_filter:#{has_filter}")
      end

      tags = %W[force_pulls:true force_issues:#{issues_only} is_default_query:#{is_default_query} is_self_assigned:#{is_self_assigned} is_self_authored:#{is_self_authored}]
      search_tags.concat(tags)
      search_tags
    end

    def specified_tab
      return @specified_tab if defined?(@specified_tab)
      params[:tab].presence || "discussion"
    end

    def stats
      @_stats ||= ::PageStats.new(
        controller_name: "pull_request",
        action_name: action_name,
        viewer: current_user,
        pjax: pjax?,
      )
    end

    # Overrides the default `tree_name` method which pulls current tree from the URL or default branch
    # to prefer the pull requests head branch by default.
    def tree_name
      if @pull && @pull.open?
        @pull.head_ref_name
      elsif @pull
        @pull.head_sha
      else
        super
      end
    end

    private

    def exclude_item_types
      if current_user&.site_admin?
        params.fetch(:exclude_item_types, [])
      else
        []
      end
    end
  end
end
