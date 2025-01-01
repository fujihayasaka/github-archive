# typed: true
# frozen_string_literal: true

module Voltron
  class PullRequestsFragmentsController < AbstractRepositoryController
    include ConditionalAccessDependency
    include ControllerMethods::Codespaces
    include ControllerMethods::PullRequests
    include FragmentController
    include GateRequestHelper
    include GitHub::RateLimitedRequest

    rate_limit_requests max: 5000, ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, key: :rate_limit_key_by_ip

    # Don't require header in dev or review lab, to simplify nginx configs
    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }
    before_action :require_pull_request
    before_action :mark_pull_notification_as_read, only: :pull_request_layout
    before_action :expires_now
    around_action :record_stats

    after_action :flush_badge_timer_metrics, only: [:conversation_content]
    after_action :record_canary_metrics, only: [:pull_request_layout]

    helper_method :cpu_timer

    javascript_bundle :codespaces
    javascript_bundle :diffs
    javascript_bundle :scanning
    javascript_bundle :"code-menu"
    javascript_bundle :"copilot-coding-agent-status"
    stylesheet_bundle :"pull-requests"

    preload_features PullRequestsController::SHOW_FEATURES
    preload_features [:benchmark_mergebox, :mergebox_react_partial], only: [:conversation_content, :conversation_sidebar, :pull_request_layout]
    preload_features [:optimize_participant_list_for_large_orgs], only: [:conversation_sidebar]

    layout "repository"

    before_action do
      @page_responsive = true
    end

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      ApplicationRecord::Notify,
      only: [:pull_request_layout]

    depends_on_clusters ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::RepositoriesActionsChecks,
      only: [:pull_request_layout], optional: true

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Memex,
      ApplicationRecord::Iam,
      only: [:conversation_sidebar]

    depends_on_clusters ApplicationRecord::Mysql5,
      ApplicationRecord::Spokes,
      ApplicationRecord::Copilot,
      optional: true,
      only: [:conversation_sidebar]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Iam,
      ApplicationRecord::Spokes,
      only: [:conversation_content]

    depends_on_clusters ApplicationRecord::Mysql5,
      optional: true,
      only: [:conversation_content]

    def pull_request_layout # rubocop:todo GitHub/UseRestfulActions
      @specified_tab = "discussion"
      set_hovercard_subject(current_pull_request)

      render "voltron/pull_requests/pull_request_layout", locals: {
        repo: current_repository,
        pull_request: current_pull_request,
        gate_requests: gate_requests_for(pull_request: current_pull_request, user: current_user),
      }
    end

    def conversation_content # rubocop:todo GitHub/UseRestfulActions
      pull_node = stats.record_distribution("fetch_data.no_graphql", include_net: true) do
        PullRequest::ShowLoader.issue_node \
          current_pull_request,
          current_repository,
          current_user,
          cap_filter: cap_filter,
          pagination_params: {
            per_page: params[:timeline_per_page],
            exclude_item_types: exclude_item_types,
          },
          cpu_timer: cpu_timer
      end
      # Removed unused variable `add_debugging_for_repo`
      render "pull_requests/_timeline",
        locals: {
          pull_node: pull_node,
          add_debugging_for_repo: add_debugging_for_repo?
        },
        layout: fragment_layout
    end

    def conversation_sidebar # rubocop:todo GitHub/UseRestfulActions
      render "pull_requests/_sidebar", layout: fragment_layout, locals: { pull: current_pull_request, deferred_content: true, add_debugging_for_repo: add_debugging_for_repo? }
    end

    private

    def require_voltron_header
      if request.headers["HTTP_X_GITHUB_USE_VOLTRON_PULL_REQUESTS_SHOW"] != "1"
        render_404
      end
    end

    def require_pull_request
      return render_404 if current_pull_request&.hide_from_user?(current_user)
      return if current_pull_request

      redirect_to issue_path(current_repository.owner, current_repository, params[:id])
    end

    def add_debugging_for_repo?
      current_repository&.feature_flag_enabled?(:sidebar_repo_debugging, default: false)
    end

    def current_pull_request # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      # Assigning @pull here rather than using memoize helper makes @pull available in the helper called from
      # app/views/shared/_open_in_github_dev.html.erb. If we didn't do this we'd have to plumb through the PR as
      # a view across multiple nested partials to get it down there...
      return @pull if defined?(@pull)
      @pull = PullRequest.with_number_and_repo(params[:id].to_i, current_repository, include: :issue)
    end

    def mark_pull_notification_as_read
      async_mark_thread_as_read current_pull_request.issue
    end

    def record_stats
      stats.entity = current_pull_request
      stats.add_tags "voltron:true"
      GitHub.current_span&.add_attributes({ "gh.repo.id" => current_repository.id })

      stats.instrument_controller_action do
        yield
        response.successful?
      end
    end

    # Implemented for use in the view, overriding the default `false` value
    def defer_commit_badges?
      true
    end

    # Implemented for use in the view, overriding the default `false` value
    def defer_status_check_rollups?
      true
    end

    def route_supports_advisory_workspaces?
      true
    end

    def cpu_timer # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @_cpu_timer ||= CpuTimer.new(
        "badge.request.total",
        tags: [
          "resource:pull_requests",
          "logged_in:#{current_user.present?}",
        ],
      )
    end

    def flush_badge_timer_metrics
      cpu_timer.flush
    end

    def record_canary_metrics
      return unless current_pull_request.open? && current_pull_request.created_at > 1.week.ago
      return unless current_repository.feature_flag_enabled?(:prs_stale_canary, default: true)

      stale = current_pull_request.stale?
      GitHub.dogstats.increment "pull_request.canary.stale_check", tags: ["stale:#{stale}"]
      return unless stale

      push = current_pull_request.latest_unsynced_push_to_head_ref
      if push
        GitHub.dogstats.distribution_timing_since(
          "pull_request.canary.stale.since_pushed",
          push.pushed_at
        )
      else
        GitHub.dogstats.increment "pull_request.canary.stale.push_not_found"
      end
    end
  end
end
