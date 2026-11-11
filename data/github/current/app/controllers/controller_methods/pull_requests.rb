# typed: true
# frozen_string_literal: true

module ControllerMethods
  module PullRequests
    extend ActiveSupport::Concern
    extend T::Helpers

    include RelayHelper
    include ::PullRequests::MergeboxHelper
    include ::PullRequests::NewFilesChangedHelper
    include ::PullRequests::OverviewHelper

    requires_ancestor { ApplicationController }

    SHOW_ACTION_NAMES = [:show, :issue_layout, :issue_conversation_content].freeze
    PR_SHOW_ANONYMOUS_RATE_LIMIT_MAX = 10_000

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

    def parsed_issues_query
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

    def use_strict_loading
      !action_name.nil? && SHOW_ACTION_NAMES.include?(action_name.to_sym)
    end

    def current_issue
      return @current_issue if defined?(@current_issue)

      # if there is no `id` set from the route, then we can't load the issue.
      issue_number = params[:id].to_i
      return @current_issue = nil if issue_number.zero?

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
          @current_issue = issues.includes(*includes).find_by_number(issue_number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

    # Handle route redirect to the new overview page if the feature flags are enabled
    # This is used internally for testing the new overview page by making it the forced default
    def handle_overview_route_redirects
      return if request.xhr? # only redirect hard-navs to give an escape hatch without needing to disable the feature flag
      return unless current_repository
      return unless current_user
      return unless FeatureFlag.vexi.enabled?(:prs_overview_default, current_user, default: false)

      if pr_overview_feature_enabled_for_user?(current_user, params)
        # don't skew request times for the original action in telemetry
        GitHub::TaggingHelper.override_action_tag(env: env, action: "overview_redirect")

        redirect_to "/#{current_repository.name_with_display_owner}/pull/#{params[:id]}/overview"
      end
    rescue => e
      GitHub.dogstats.increment("pull_request.overview_redirect.error")
      Rails.logger.error("[handle_overview_route_redirects] #{e.class}: #{e.message}")
    end

    private

    def exclude_item_types
      if current_user&.site_admin?
        params.fetch(:exclude_item_types, [])
      else
        []
      end
    end

    def use_new_anonymous_rate_limit?
      !logged_in? && FeatureFlag.vexi.enabled?(:pr_show_anonymous_rate_limit, nil, default: false)
    end

    # Private: Checks if pull requests are enabled for the repository.
    def require_pull_requests_enabled
      repo = current_repository

      # No-op if there's no repo
      return unless repo

      # Render 404 if pull requests are disabled
      render_404 unless PullRequestActivationConfig.new(repo).pull_requests_enabled?
    end

    def require_can_create_pull_request
      repo = current_repository
      return unless repo

      render_404 unless PullRequestCreationConfig.new(repo).pull_request_creation_allowed_for?(current_user)
    end

    def require_pull_request_creation_cap_not_reached
      repo = current_repository
      return unless repo

      unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access
      pull_request_attributes = PullRequestCreationConfig::PullRequestAttributes.new(
        user: current_user,
        draft: unsafe_params[:draft] == "on"
      )
      return unless PullRequestCreationConfig.new(repo).pull_request_exceeds_limit?(pull_request_attributes)

      flash[:error] = "Pull request creation failed. Validation failed: open pull request limit has been reached for this user"
      redirect_to compare_path(
        repo,
        [unsafe_params[:base], unsafe_params[:head]].compact.join("..."),
        expand: true,
        stack: unsafe_params[:create_stack].present?
      )
    end

    def add_debugging_for_repo?
      current_repository&.feature_flag_enabled?(:sidebar_repo_debugging, default: false)
    end

    # Renders conversation content (timeline) for a pull request as an HTML fragment.
    # Used by both the Voltron fragments controller (primary SSR) and the partials
    # controller (graceful timeout retry).
    #
    # pull_request - The PullRequest to render content for.
    # layout       - The layout to use for rendering (default: false for no layout).
    # cpu_timer    - Optional CpuTimer for badge metrics (default: nil).
    #
    # Returns nothing (renders directly).
    def render_conversation_content_html(pull_request, layout: false, cpu_timer: nil)
      controller = T.unsafe(self)
      render "pull_requests/_conversation_timeline_react", locals: {
        pull_node: controller.create_pull_node(pull_request),
        pull_request: pull_request,
        gate_requests: controller.gate_requests_for(pull_request: pull_request, user: current_user),
        current_repository: current_repository,
        current_user: current_user,
      },
      layout: layout
    end

    def gracefully_degrade_from_timeout_nine_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_nine, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_eight_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_eight, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_seven_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_seven, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_six_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_six, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_five_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_five, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_four_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_four, current_repository, default: false)
    end

    def gracefully_degrade_from_timeout_testing_enabled?
      FeatureFlag.vexi.enabled?(:prs_voltron_graceful_timeout_testing, current_repository, default: false)
    end

    def graceful_timeout_threshold
      if gracefully_degrade_from_timeout_testing_enabled?
        # 1 second for testing purposes on production to verify that graceful degradation is working as expected
        return 1
      elsif gracefully_degrade_from_timeout_four_enabled?
        return 4
      elsif gracefully_degrade_from_timeout_five_enabled?
        return 5
      elsif gracefully_degrade_from_timeout_six_enabled?
        return 6
      elsif gracefully_degrade_from_timeout_seven_enabled?
        return 7
      elsif gracefully_degrade_from_timeout_eight_enabled?
        return 8
      elsif gracefully_degrade_from_timeout_nine_enabled?
        return 9
      end

      GitHub.default_request_timeout
    end

    def should_gracefully_degrade_from_timeout?
      graceful_timeout_threshold < GitHub.default_request_timeout
    end
  end
end
