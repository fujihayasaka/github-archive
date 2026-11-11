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
    include PullRequests::ReactDependency

    rate_limit_requests \
      max: :rate_limit_max_for_request,
      ttl: :rate_limit_ttl_for_request,
      key: :rate_limit_key_for_request

    # Don't require header in dev or review lab, to simplify nginx configs.
    before_action :require_voltron_header, unless: -> {
      T.bind(self, Voltron::PullRequestsFragmentsController)
      Rails.env.development? || GitHub.dynamic_lab?
    }
    before_action :require_pull_request
    before_action :handle_overview_route_redirects, only: :pull_request_layout
    before_action :mark_pull_notification_as_read, only: :pull_request_layout
    before_action :expires_now
    before_action :require_pull_requests_enabled
    around_action :record_stats

    after_action :flush_badge_timer_metrics, only: [:conversation_content]
    after_action :record_canary_metrics, only: [:pull_request_layout]

    rescue_from_timeout_without_replay only: [:conversation_content], if: :should_gracefully_degrade_from_timeout? do |_boom|
      T.bind(self, Voltron::PullRequestsFragmentsController)

      tags = ["with_retry:false", "graceful_timeout_threshold:#{graceful_timeout_threshold}"]
      GitHub.dogstats.increment "pull_request.conversation_content.graceful_timeout", tags: tags

      # Note: we don't report the boom here because we are attempting a retry
      # If the rety fails, that failure will be reported separately, and reporting both would be redundant and noisy.

      # Render an <include-fragment> that will retry fetching timeline via the non-Voltron
      # endpoint. This avoids exposing 403 vs 404 to unauthorized users, since the
      # PullRequestPartialsController uses AbstractRepositoryController access control which
      # consistently returns 404 for unauthorized access.
      render partial: "site/pull_request_timeline_timeout_retry",
             locals: { refetch_url: pull_request_conversation_content_path(current_repository.owner, current_repository, current_pull_request, timeline_per_page: 1, graceful_retry: 1) }
    end

    helper_method :cpu_timer

    javascript_bundle :codespaces
    javascript_bundle :diffs
    javascript_bundle :scanning
    javascript_bundle :"code-menu"
    javascript_bundle :"pull-requests"
    stylesheet_bundle :"pull-requests"
    stylesheet_bundle "copilot-code-review"
    stylesheet_bundle :actions

    preload_features PullRequestsController::SHOW_FEATURES
    preload_features [:optimize_participant_list_for_large_orgs, :optimize_reviewer_list_for_large_orgs], only: [:conversation_sidebar]

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
      ApplicationRecord::Copilot,
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

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Repositories,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Iam,
      ApplicationRecord::Spokes,
      # Memex and RepositoriesPushes are needed to load the sidebar data for React requests
      # that don't split sidebar and content into separate requests.
      ApplicationRecord::Memex,
      ApplicationRecord::RepositoriesPushes,
      only: [:conversation_content]

    depends_on_clusters ApplicationRecord::Mysql5,
      ApplicationRecord::Copilot,
      ApplicationRecord::RepositoriesActionsChecks,
      optional: true,
      only: [:conversation_content]

    def pull_request_layout # rubocop:todo GitHub/UseRestfulActions
      @specified_tab = "discussion"
      respond_to do |format|
        format.html do
          set_hovercard_subject(current_pull_request)

          render_pull_requests_react(
            pull: current_pull_request,
            url_override: true,
          )
        end

        format.json do
          render_react_json(
            payload: PullRequests::ReactPayloads::PullRequestsConversationsPayload.new(
              locked: current_repository_locked_for_migration?,
              pull_request: @pull,
              current_user: current_user,
              default_merge_method: default_merge_method_for_user(@pull, current_user)
            )
          )
        end
      end
    end

    def conversation_content # rubocop:todo GitHub/UseRestfulActions
      respond_to do |format|
        format.html do
          timeout_seconds = should_gracefully_degrade_from_timeout? ? graceful_timeout_threshold : nil
          GitHub::Timer.timeout(timeout_seconds) do
            render_conversation_content_html(current_pull_request, layout: fragment_layout, cpu_timer: cpu_timer)
          end
        end

        format.json do
          head :no_content
        end
      end
    end

    def conversation_sidebar # rubocop:todo GitHub/UseRestfulActions
      respond_to do |format|
        format.html do
          render "pull_requests/_sidebar", layout: fragment_layout, locals: { pull: current_pull_request, deferred_content: false }
        end

        format.json do
          head :no_content
        end
      end
    end

    private

    def global_nav_selected_link
      :repo_pulls
    end

    def require_voltron_header
      if request.headers["HTTP_X_GITHUB_USE_VOLTRON_PULL_REQUESTS_SHOW"] != "1"
        render_404
      end
    end

    def require_pull_request
      return render_404 if current_pull_request&.hide_from_user?(current_user)
      return render_404 if current_pull_request&.archived_and_hidden_from?(current_user)
      return render_404 if current_pull_request&.killed_and_hidden_from?(current_user)
      return if current_pull_request

      redirect_to issue_path(current_repository.owner, current_repository, params[:id])
    end

    def current_pull_request # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      # Assigning @pull here rather than using memoize helper makes @pull available in the helper called from
      # app/views/shared/_open_in_github_dev.html.erb. If we didn't do this we'd have to plumb through the PR as
      # a view across multiple nested partials to get it down there...
      return @pull if defined?(@pull)
      @pull = PullRequest.with_number_and_repo(params[:id].to_i, current_repository, include: :issue)

      if @pull && FeatureFlag.vexi.enabled?(:prs_push_pr_id_to_failbot, current_repository, default: false)
        Failbot.push("gh.pull_request.id": @pull.id)
      end

      @pull
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
      return unless current_repository&.feature_flag_enabled?(:prs_stale_canary, default: true)

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

    # Private: Returns the target entity for user name display configuration.
    #
    # This method determines which entity's user name display settings should be used
    # when rendering user names in the pull request context. For pull requests, we use
    # the repository's organization configuration if available.
    #
    # Returns an Organization or nil if the repository is not owned by an organization.
    def target_for_user_name_display_configuration
      current_repository&.organization
    end

    def rate_limit_max_for_request
      use_new_anonymous_rate_limit? ? PR_SHOW_ANONYMOUS_RATE_LIMIT_MAX : 5000
    end

    def rate_limit_ttl_for_request
      use_new_anonymous_rate_limit? ? GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL : GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL
    end

    def rate_limit_key_for_request
      use_new_anonymous_rate_limit? ? default_rate_limit_key : rate_limit_key_by_ip
    end
  end
end
