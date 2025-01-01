# typed: true
# frozen_string_literal: true

module Voltron
  class IssuesFragmentsController < AbstractRepositoryController
    Self = T.type_alias { Voltron::IssuesFragmentsController }

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
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
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Spokes,
      optional: false, only: [:issue_conversation_sidebar]

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
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
      optional: false, only: [:issue_conversation_content, :issue_layout]

    ISSUES_SHOW_VOLTRON_HEADER = "HTTP_X_GITHUB_USE_VOLTRON_ISSUES_SHOW".freeze

    include ConditionalAccessDependency
    include ControllerMethods::Issues
    include FragmentController
    include GitHub::RateLimitedRequest
    include IssuesHelper
    include IssuesReactHelper
    include Issues::RateLimitsDependency

    javascript_bundle :"issues-react", only: [:issue_conversation_content, :issue_layout], if: -> { T.bind(self, Self); issue_react_enabled? }

    def self.react_bundle_name
      "issues-react"
    end

    # action optimization for issues react flow
    skip_before_action :ask_the_gatekeeper, if: proc { |c| T.bind(self, Self); c.action_name == "issue_conversation_content" && issue_react_enabled? }
    skip_before_action :privacy_check, if: proc { |c| T.bind(self, Self);  c.action_name == "issue_conversation_content" && issue_react_enabled? }
    skip_before_action :ensure_advisory_workspace_allowed, if: proc { |c| T.bind(self, Self); c.action_name == "issue_conversation_content" && issue_react_enabled? }

    # Don't require header in dev or review lab, to simplify nginx configs
    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }
    before_action :handle_issue_transfer_deletion_or_conversion, only: [:issue_layout]
    before_action :render_empty_if_no_issue, only: [:issue_conversation_content, :issue_conversation_sidebar]
    before_action :require_issue_for_layout, only: [:issue_layout]

    around_action :track_and_report_render_view_time, only: [:issue_layout, :issue_conversation_content, :issue_conversation_sidebar]
    around_action :track_and_report_graphql_executions, only: [:issue_layout, :issue_conversation_content, :issue_conversation_sidebar]
    around_action :track_and_report_mysql_executions, only: [:issue_layout, :issue_conversation_content, :issue_conversation_sidebar]

    before_action do
      T.bind(self, Self)
      set_page_responsive
    end

    skip_before_action :cap_pagination, unless: :robot?

    after_action :flush_badge_timer_metrics, only: [:issue_conversation_content]
    helper_method :cpu_timer

    javascript_bundle :issues, unless: -> { T.bind(self, Self); issue_react_enabled? }
    javascript_bundle :"structured-issues", unless: -> { T.bind(self, Self); issue_react_enabled? }
    javascript_bundle :codespaces, only: [:issue_conversation_sidebar]


    preload_features IssuesController::SHOW_WITH_REACT_FEATURES + IssuesController::DEFAULT_FEATURES, only: [:issue_conversation_content, :issue_conversation_sidebar]

    rate_limit_requests \
      max: ISSUES_BOT_RATE_LIMIT_MAX,
      ttl: 1.minute,
      key: :issues_bot_rate_limit_key,
      if: :issues_bot_rate_limiting_enabled?,
      at_limit: :issues_bot_rate_limit_at_limit

    layout "repository"

    memoize def current_issue_for_layout # rubocop:todo GitHub/UseRestfulActions
      includes = [
        :labels,
        :milestone,
        :pinned_issue,
        pull_request: [:user],
      ]

      if issue_react_enabled?
        includes << :user
      end

      repo_issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      repo_issues.includes(*includes).find_by_number(params[:id].to_i)
    end

    def issue_layout # rubocop:todo GitHub/UseRestfulActions
      # we are manually setting current_issue here so future usage of current_issue helper return
      # our custom memoized version
      @current_issue = @issue = current_issue_for_layout
      return render_404 if render_not_found?(current_issue)
      set_headers_and_hovercard_subject(current_issue)

      react_mode = issue_react_enabled?

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

          track_execution_time("mark_thread_as_read") do
            async_mark_thread_as_read current_issue
          end

          if !react_mode
            set_rails_tag
            project_cards = []
            tags = %W[
            is_empty:#{project_cards.empty? && !current_issue.has_timeline_items?}
            issue_unfurl:true]

            issue_node = Issue::ShowLayoutLoader.issue_node \
              current_issue,
              current_repository,
              current_user,
              cap_filter: cap_filter

            HierarchyCommands::CheckDatabaseSync.new(
              issue: issue_node.issue,
              repository: current_repository,
              viewer: current_user,
            ).call
          else
            set_react_tag
            if params[:id].to_i > 0
              set_preload_header([
                GraphQLRequest.new(
                  query: ISSUE_VIEWER_SECONDARY_VIEW_QUERY_PATH,
                  variables: {
                    owner: current_repository.owner.display_login,
                    repo: current_repository.name,
                    number: params[:id].to_i,
                    markAsRead: true,
                  }
                )
              ])
            end
            issue_node = nil
          end

          layout = if render_layout?
            if logged_in?
              :default
            elsif react_mode
              "repository_with_container"
            else
              :default
            end
          else
            false
          end

          render "issues/show",
            layout: layout,
            locals: {
              repo: current_repository,
              issue_node: issue_node,
              project_cards: project_cards,
              tags: tags,
              tracking_issues: tracking_issues,
              fragment_layout: true,
              react_mode: react_mode,
              show_announcements: true,
            }
        end
      end
    end

    def issue_conversation_content # rubocop:todo GitHub/UseRestfulActions
      if issue_react_enabled?
        path = "/#{current_repository.name_with_display_owner}/issues/#{params[:id].to_i}"
        url_override = "https://#{T.must(request).host}#{path}"
        return if issue_react_show_handler(current_issue: current_issue, url_override: url_override, path_override: path, skip_layout: true)
      end

      @issue = current_issue
      issue_node = Issue::ShowLoader.issue_node \
        current_issue,
        current_repository,
        current_user,
        cap_filter: cap_filter,
        cpu_timer: cpu_timer

      set_rails_tag
      render "issues/_issues_show_main_section",
             locals: {
               issue: current_issue,
               issue_node: issue_node,
               tags: []
             },
             layout: fragment_layout
    end

    def current_issue_for_sidebar # rubocop:todo GitHub/UseRestfulActions
      includes = [
        :labels,
        :milestone,
        :pinned_issue
      ]

      repo_issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      repo_issues.includes(*includes).find_by_number(params[:id].to_i)
    end

    def issue_conversation_sidebar # rubocop:todo GitHub/UseRestfulActions
      if issue_react_enabled?
        # using react - render empty sidebar response and return
        head :ok
        return
      end

      @current_issue = @issue = current_issue_for_sidebar
      set_rails_tag

      render "issues/_sidebar",
             locals: {
               issue: current_issue,
               project_cards: [],
               deferred_content: true,
             },
             layout: fragment_layout

    end

    def defer_status_check_rollups? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    def defer_commit_badges? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    private

    def require_voltron_header
      render_404 if T.must(request).headers[ISSUES_SHOW_VOLTRON_HEADER] != "1"
    end

    def require_issue_for_layout
      return if current_issue_for_layout

      render_404
    end

    def render_empty_if_no_issue
      return if issue_react_enabled? && require_issue_simple
      return if current_issue

      head :ok
    end

    def require_issue_simple
      issues = use_strict_loading ? current_repository.issues.strict_loading : current_repository.issues
      @current_issue = issues.find_by_number(params[:id].to_i)
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

      @issue.normalized_tracking_issues(
        viewer: current_user,
        cap_filter: cap_filter
      )
    end

    def tracking_issues_enabled?
      !GitHub.enterprise? || current_repository&.owner&.feature_enabled?(:tasklist_block)
    end
  end
end
