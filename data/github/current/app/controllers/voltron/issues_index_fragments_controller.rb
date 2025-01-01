# typed: true
# frozen_string_literal: true

module Voltron
  class IssuesIndexFragmentsController < AbstractRepositoryController
    Self = T.type_alias { Voltron::IssuesIndexFragmentsController }

    # `pageSize` is specific to React
    ALLOWED_PARAMS = [:page, :per_page, :pageSize, :q].freeze

    include ConditionalAccessDependency
    include ControllerMethods::Issues
    include FragmentController
    include GitHub::RateLimitedRequest
    include IssuesHelper
    include IssuesReactHelper
    include ReactHelper
    include Issues::RateLimitsDependency

    depends_on_clusters \
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      optional: false

    depends_on_clusters \
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Copilot,
      ApplicationRecord::Iam,
      ApplicationRecord::Memex,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Notify,
      ApplicationRecord::Permissions,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::Spokes,
      optional: true

    rate_limit_requests \
      max: ISSUES_INDEX_WITHOUT_REFERER_RATE_LIMIT_MAX,
      ttl: 1.minute,
      key: :issues_index_rate_limit_key,
      if: :issues_index_without_referer_limits_enabled?,
      at_limit: :issues_index_rate_limit_at_limit

    ISSUES_INDEX_VOLTRON_HEADER = "HTTP_X_GITHUB_USE_VOLTRON_ISSUES_INDEX".freeze

    javascript_bundle :issues, unless: -> { T.bind(self, Self); is_issue_react_index_enabled? }
    javascript_bundle :"structured-issues", unless: -> { T.bind(self, Self); is_issue_react_index_enabled? }
    javascript_bundle :"issues-react", if: -> { T.bind(self, Self); is_issue_react_index_enabled? }

    layout "repository", only: [:layout]

    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }

    before_action do
      T.bind(self, Self)
      set_page_responsive
    end

    # action optimization for issues react flow
    skip_before_action :ask_the_gatekeeper, if: proc { |c| T.bind(self, Self); c.action_name == "content" && is_issue_react_index_enabled? }
    skip_before_action :privacy_check, if: proc { |c| T.bind(self, Self);  c.action_name == "content" && is_issue_react_index_enabled? }
    skip_before_action :ensure_advisory_workspace_allowed, if: proc { |c| T.bind(self, Self); c.action_name == "content" && is_issue_react_index_enabled? }

    around_action :track_and_report_graphql_executions, only: [:content]
    around_action :track_and_report_mysql_executions, only: [:layout]

    skip_before_action :cap_pagination, unless: :robot?

    preload_features IssuesController::INDEX_WITH_REACT_FEATURES + IssuesController::DEFAULT_FEATURES, only: [:content]

    def self.react_bundle_name
      "issues-react"
    end

    def layout # rubocop:disable GitHub/UseRestfulActions
      set_initial_tags
      # Way to detect pulls only for the title
      self.pulls_only = query_string_includes_pr? unless GitHub.flipper[:issues_advanced_search].enabled?(current_user)

      if logged_in? && !pulls_only? && GitHub.flipper[:issues_react_benchmark_graphql].enabled?
        BenchmarkGraphqlJob.perform_later(current_user&.id, current_repository.id, nil)
      end

      document_title_base = pulls_only? ? "Pull requests" : "Issues"

      document_title_suffix = current_repository ? current_repository.name_with_display_owner : "GitHub"
      document_title = "#{document_title_base} · #{document_title_suffix}"

      document_link_to = pulls_only? ? :repo_pulls : :repo_issues

      if is_issue_react_index_enabled?
        set_react_tag
      else
        set_rails_tag
      end

      respond_to do |format|
        format.html do
          render "issues/index", locals: {
            document_title_override: document_title,
            document_link_override: document_link_to,
            pulls_only: pulls_only?,
            fragment_layout: true,
            react_mode: is_issue_react_index_enabled?,
          }
        end
      end
    end

    def content # rubocop:disable GitHub/UseRestfulActions
      set_initial_tags
      self.pulls_only = index_flow.pulls_only unless GitHub.flipper[:issues_advanced_search].enabled?(current_user)

      if is_issue_react_index_enabled?
        url_override = "https://#{T.must(request).host}#{path_override}"
        return if issue_react_index_handler(pulls_only: pulls_only?, url_override: url_override, path_override: path_override, skip_layout: true)
      end

      return safe_redirect_to(index_flow.redirect_path) if index_flow.needs_redirection?

      if pulls_only?
        # Overwrite tags passed to datadog to facilitate filtering by controller and action
        # Log requests as controller: pull_requests, action: index
        GitHub::TaggingHelper.override_controller_tag(env: env, controller: "pull_requests")
        GitHub.current_span&.set_attribute(GitHub::TaggingHelper::CONTROLLER_TAG, "pull_requests")
      end

      query = index_flow.query
      self.parsed_issues_query = Search::Queries::IssueQuery.parse(query, current_user)

      query_error  = false
      issues       = []
      open_count   = 0
      closed_count = 0

      begin
        # When searching exclusively issues, we do not need to prefilling the comment counts.
        # Once a a search happens exclusively in issues, theres is not need to load the pull requests counts for that.
        # the `IssueListItem` in app/view_models/issues/issue_list_item.rb:154 takes care of a possible fallback and memorization.
        tags = query_parsed_search_tags

        result = Issue::SearchResult.search(
          query:              parsed_issues_query,
          current_user:       current_user,
          remote_ip:          T.must(request).remote_ip,
          repo:               current_repository,
          force_pulls:        index_flow.force_pulls?,
          page:               params[:page],
          show_spam_to_staff: current_user&.show_spammy_issues_to_staff_enabled?,
          tags:               tags,
          context:            "#{T.must(self.class.name).demodulize.underscore}-#{__method__}-#{pulls_only? ? "pull_requests" : "issues"}",
        )

        issues       = result[:issues]
        open_count   = result[:open_count]
        closed_count = result[:closed_count]
      rescue ElastomerClient::Client::Error => boom
        Failbot.push app: "github-user"
        Failbot.report boom
        query_error  = true
      end

      # disallow robots if labels or milestone is given
      label_or_milestone = parsed_issues_query.assoc(:label) || parsed_issues_query.assoc(:milestone)
      if robot? && label_or_milestone
        return render_404
      end

      if pulls_only?
        override_analytics_location "/<user-name>/<repo-name>/pull_requests/index"
      else
        set_rails_tag # set react tracking rails tag only if not pulls only (+ after redirections that happen above)
      end

      strip_analytics_query_string

      milestones_count = current_repository.milestones.open_milestones.count
      labels_count = current_repository.labels.count

      view = Issues::IndexView.new query: query, issues: issues,
                            repo: current_repository, pulls_only: pulls_only?,
                            current_user: current_user,
                            cap_view_filter: cap_view_filter

      respond_to do |format|
        format.html do
          render partial: "issues/issues_index_main_section", locals: {
            view: view,
            issues: issues,
            pulls_only: pulls_only?,
            fragment_layout: true,
            query: query,
            query_error: query_error,
            open_count: open_count,
            closed_count: closed_count,
            milestones_count: milestones_count,
            labels_count: labels_count,
            tags: query_parsed_search_tags,
            render_issue_react_opt_in: render_issue_react_index_opt_in?,
            show_announcements: true,
          }
        end
      end
    end

    def defer_status_check_rollups? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    def defer_commit_badges? # rubocop:todo GitHub/UseRestfulActions
      true
    end

    private

    def set_initial_tags
      set_staff_tag
    end

    def path_override # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @path_override if defined?(@path_override)

      path_override = "/#{current_repository.name_with_display_owner}/issues"
      url_params = permitted_url_params
      path_override += "?#{url_params.to_query}" if url_params.present?

      @path_override = path_override
    end

    def permitted_url_params
      params.permit!.to_h.slice(*ALLOWED_PARAMS).reject { |_, v| v.blank? }
    end

    def index_flow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @index_flow if defined?(@index_flow)

      @index_flow ||= Issue::ControlFlow.new(
        params: params,
        repo:   current_repository,
        components: parsed_issues_query,
        current_user: current_user,
        current_path: path_override,
      )
    end

    def require_voltron_header
      render_404 if T.must(request).headers[ISSUES_INDEX_VOLTRON_HEADER] != "1"
    end

    def set_page_responsive
      @page_responsive = true
    end
  end
end
