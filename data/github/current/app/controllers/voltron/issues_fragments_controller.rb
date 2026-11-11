# typed: true
# frozen_string_literal: true

module Voltron
  class IssuesFragmentsController < AbstractRepositoryController
    Self = T.type_alias { Voltron::IssuesFragmentsController }

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Notify,
      ApplicationRecord::Permissions,
      ApplicationRecord::Repositories,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::Spokes,
      ApplicationRecord::Profiles,
      optional: false, only: [:issue_conversation_content, :issue_layout]

    # Collab cluster failures are handled gracefully via with_collab_cluster_resilience
    depends_on_clusters ApplicationRecord::Collab,
      optional: true, only: [:issue_conversation_content, :issue_layout]

    ISSUES_SHOW_VOLTRON_HEADER = "HTTP_X_GITHUB_USE_VOLTRON_ISSUES_SHOW".freeze

    include ConditionalAccessDependency
    include ControllerMethods::Issues
    include FragmentController
    include GitHub::RateLimitedRequest
    include IssuesHelper
    include IssuesReactHelper
    include Issues::RateLimitsDependency
    include Issues::RepositoryClusterDependency

    javascript_bundle :"issues-react", only: [:issue_conversation_content, :issue_layout]
    def self.react_bundle_name
      "issues-react"
    end

    # action optimization for issues react flow
    skip_before_action :ask_the_gatekeeper, if: proc { |c| T.bind(self, Self); c.action_name == "issue_conversation_content" }
    skip_before_action :privacy_check, if: proc { |c| T.bind(self, Self);  c.action_name == "issue_conversation_content" }
    skip_before_action :ensure_advisory_workspace_allowed, if: proc { |c| T.bind(self, Self); c.action_name == "issue_conversation_content" }

    # Don't require header in dev or review lab, to simplify nginx configs
    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }
    before_action :set_vary_relay_cache
    before_action :handle_issue_transfer_deletion_or_conversion, only: [:issue_layout]
    before_action :render_empty_if_no_issue, only: [:issue_conversation_content]
    before_action :require_and_preload_issue_for_layout, only: [:issue_layout]

    around_action :track_and_report_render_view_time, only: [:issue_layout, :issue_conversation_content]
    around_action :track_and_report_graphql_executions, only: [:issue_layout, :issue_conversation_content]
    around_action :track_and_report_mysql_executions, only: [:issue_layout, :issue_conversation_content]
    # Use prepend_around_action so context is set BEFORE before_action callbacks run.
    # This ensures loaders have the resilience context when loading issue data.
    #
    # Security note: prepend_around_action is generally discouraged per
    # https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/filter-chains/
    # but is required here so the resilience and time-budget guards wrap before_action
    # callbacks (e.g. require_and_preload_issue_for_layout) that issue DB queries.
    # These methods only set DB connection roles and error-handling context — they
    # do NOT bypass authentication, authorization, or Conditional Access Policy checks.
    # This follows the same pattern as use_repository_cluster_replicas in
    # PullRequestsController and other controllers.
    #
    # Prepended ordering (outermost → innermost): time_budget_guard → collab_resilience.
    # Regular around_actions (track/report wrappers) execute inside these, before the action.
    prepend_around_action :with_collab_cluster_resilience, only: [:issue_layout, :issue_conversation_content]
    prepend_around_action :with_repository_time_budget_guard, only: [:issue_layout, :issue_conversation_content]

    before_action do
      T.bind(self, Self)
      set_page_responsive
    end

    skip_before_action :cap_pagination, unless: :robot?

    after_action :flush_badge_timer_metrics, only: [:issue_conversation_content]
    helper_method :cpu_timer

    preload_features IssuesController::SHOW_WITH_REACT_FEATURES + IssuesController::DEFAULT_FEATURES, only: [:issue_conversation_content]

    rate_limit_requests \
      max: ISSUES_BOT_RATE_LIMIT_MAX,
      ttl: 1.minute,
      key: :issues_bot_rate_limit_key,
      if: :issues_bot_rate_limiting_enabled?,
      at_limit: :issues_bot_rate_limit_at_limit

    layout "repository"

    # Minimal issue loader for cache hit scenarios - skips most eager loading
    # since we only need the issue for 404/redirect checks and basic rendering.
    # Still loads :user (view needs @issue.user) and :pull_request (render_not_found? checks it)
    memoize def current_issue_for_layout_minimal # rubocop:todo GitHub/UseRestfulActions
      repo_issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      repo_issues.includes(:user, :pull_request).find_by_number(params[:id].to_i) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    memoize def current_issue_for_layout # rubocop:todo GitHub/UseRestfulActions
      # For cache hits, use minimal query since client has cached data
      return current_issue_for_layout_minimal if should_skip_for_relay_cache?

      includes = [
        :labels,
        :milestone,
        pull_request: [:user],
      ]

      includes << :user

      repo_issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      repo_issues.includes(*includes).find_by_number(params[:id].to_i) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def issue_layout # rubocop:todo GitHub/UseRestfulActions
      return render_404 if render_not_found?(current_issue)

      # For cache hits, skip hovercard setup - hovercards are fetched separately via API
      unless should_skip_for_relay_cache?
        set_headers_and_hovercard_subject(current_issue)
      end

      if relay_cache_hit? && !issue_viewer_query_hash_matches?
        response.headers["X-Issues-React-Relay-Cache-Mismatch"] = "1"
      end

      respond_to do |format|
        format.html do
          # Legacy issues/issue/xxx routes
          if params[:legacy] && params[:id]
            redirect_to issue_path(current_repository.owner, current_repository, current_issue), status: 301
            return
          end

          if current_issue.pull_request?
            redirect_to show_pull_request_path(current_repository.owner, current_repository, current_issue)
            return
          end

          repo_without_issues = track_execution_time("repo_has_issues") do
            !current_repository.has_issues?
          end
          render_404 and return if repo_without_issues

          # Still mark as read even for cache hits - user is viewing the issue
          track_execution_time("mark_thread_as_read") do
            async_mark_thread_as_read current_issue
          end

          set_react_tag

          skip_preload = should_skip_for_relay_cache? && FeatureFlag.vexi.enabled?(:issues_preheating_secondary, current_user, default: false)

          unless skip_preload
            if params[:id].to_i > 0
              set_preload_header([
                GraphQLRequest.new(
                  name: ISSUE_VIEWER_SECONDARY_VIEW_QUERY_NAME,
                  variables: {
                    owner: current_repository.owner.display_login,
                    repo: current_repository.name,
                    number: params[:id].to_i,
                    markAsRead: true,
                  }
                )
              ])
            end
          end
          issue_node = nil

          # Track cache hit for metrics
          if should_skip_for_relay_cache?
            GitHub.dogstats.increment("request.issues.relay_cache_hit_layout",
              tags: ["controller:voltron_issues_fragments", "action:issue_layout"])
          end

          layout = if render_layout?
            if logged_in?
              layout_for_turbo_request(:default)
            else
              layout_for_turbo_request("repository_with_container")
            end
          else
            false
          end

          path = "/#{current_repository.name_with_display_owner}/issues/#{params[:id].to_i}"
          canonical_url = "https://#{T.must(request).host}#{path}"

          render "issues/show",
            layout: layout,
            locals: {
              repo: current_repository,
              issue_node: issue_node,
              # For cache hits, skip tracking issues query - React will use cached GraphQL data
              tracking_issues: should_skip_for_relay_cache? ? [] : tracking_issues,
              fragment_layout: true,
              show_announcements: true,
              canonical_url: canonical_url,
              # For cache hits, skip structured data - it's for SEO, Turbo requests are real users
              structured_data: should_skip_for_relay_cache? ? nil : get_structured_data_content
            }
        end
      end
    end

    def issue_conversation_content # rubocop:todo GitHub/UseRestfulActions
      path = "/#{current_repository.name_with_display_owner}/issues/#{params[:id].to_i}"
      url_override = "https://#{T.must(request).host}#{path}"
      if params[:timeline_page].present?
        url_override += "?timeline_page=#{params[:timeline_page]}"
        path += "?timeline_page=#{params[:timeline_page]}"
      end

      issue_react_show_handler(current_issue: current_issue, url_override: url_override, path_override: path, skip_layout: true)
    end

    def current_issue_for_sidebar # rubocop:todo GitHub/UseRestfulActions
      includes = [
        :labels,
        :milestone,
      ]

      repo_issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      repo_issues.includes(*includes).find_by_number(params[:id].to_i)
    end

    def defer_status_check_rollups? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    def defer_commit_badges? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    private

    # Enable graceful degradation for Collab cluster failures in this request.
    # This sets a request-scoped flag that Platform loaders check to decide
    # whether to return empty results instead of raising on database errors.
    #
    # Controlled by the :issues_show_collab_cluster_resilience feature flag.
    def with_collab_cluster_resilience
      if FeatureFlag.vexi.enabled?(:issues_show_collab_cluster_resilience, current_repository, default: false)
        GitHub.context.push(resilient_clusters: ["collab"]) { yield }
      else
        yield
      end
    end

    def set_vary_relay_cache
      add_headers_to_vary(%w(X-Issues-React-Relay-Cache))
    end

    def require_voltron_header
      render_404 if T.must(request).headers[ISSUES_SHOW_VOLTRON_HEADER] != "1"
    end

    def require_and_preload_issue_for_layout
      # Set @current_issue using our optimized loader that doesn't load participants
      @current_issue = @issue = current_issue_for_layout
      render_404 unless @current_issue
    end

    def render_empty_if_no_issue
      return if require_issue_simple
      return if current_issue

      head :ok
    end

    def require_issue_simple
      issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      @current_issue = issues.find_by_number(params[:id].to_i) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def set_page_responsive
      @page_responsive = true
    end

    def cpu_timer # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @_cpu_timer ||= CpuTimer.new(
        "badge.request.total",
        tags: [
          "resource:issues",
          "logged_in:#{current_user.present?}",
        ],
      )
    end

    def flush_badge_timer_metrics
      cpu_timer.flush
    end

    # Private: queries for tracking issues associated with the given issue, if the feature is enabled
    #
    # Returns an array of tracking issue hashes
    def tracking_issues
      return [] unless tracking_issues_enabled?
      return [] unless @issue

      @issue.normalized_tracking_issues( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        viewer: current_user,
        cap_filter: cap_filter
      )
    end

    def tracking_issues_enabled?
      !GitHub.enterprise? || current_repository&.owner&.feature_flag_enabled?(:tasklist_block, default: false)
    end

    # Route repository reads to replicas instead of the primary, matching
    # the IssuesController pattern. See: https://github.com/github/issues/issues/20008
    def current_repository
      with_replica_repository_cluster { super }
    end

    def ask_the_gatekeeper
      with_replica_repository_cluster { super }
    end

    def network_privilege_check
      with_replica_repository_cluster { super }
    end

    def perform_conditional_access_checks
      with_replica_repository_cluster { super }
    end
  end
end
