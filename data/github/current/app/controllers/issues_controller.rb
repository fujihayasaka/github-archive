# typed: true
# frozen_string_literal: true
require "typhoeus"
require "typhoeus/adapters/faraday"

class IssuesController < AbstractRepositoryController
  include ShowPartial
  include IssueUpdate
  include LabelEducationHelper
  include IssuesHelper
  include TimelineHelper
  include CommentsHelper
  include ReactHelper
  include HierarchyHelper
  include IssuesReactHelper
  include GitHub::RateLimitedRequest
  include ControllerMethods::Codespaces
  include ControllerMethods::Issues
  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency
  include ResilienceHelper

  around_action :with_replica_repository_cluster, only: [:update]
  around_action :track_and_report_render_view_time, only: [:show]
  around_action :track_and_report_graphql_executions, only: [:show]
  around_action :track_and_report_mysql_executions, only: [:show]
  before_action :enabled_new_issues_required, only: %w(new create)
  before_action :repo_issues_required, only: %w(choose)
  before_action :login_required,
    except: %w(index new choose show_menu_content show show_partial show_from_project pr_review_status
               linked_closing_reference)
  before_action :login_required_redirect_for_public_repo, only: [:new, :choose]
  before_action :writable_repository_required,
    except: %w(index dashboard show show_partial show_menu_content actions_menu
               redirect_to_scoped_org_dashboard show_from_project pr_review_status
               linked_closing_reference)
  before_action :issue_modifiers_only, only: %w(triage update)
  before_action :set_milestone_permission_required, only: %w(set_milestone)
  before_action :issue_required, only: %w(destroy update set_milestone dismiss_first_contribution_prompt show_from_project convert_to_discussion edit_form)
  before_action :content_authorization_required, only: %w(create update new)
  before_action :handle_issue_transfer_deletion_or_conversion, only: [:show]
  skip_before_action :cap_pagination, unless: :robot?
  skip_before_action :authorization_required, only: %w(dashboard redirect_to_scoped_org_dashboard show_menu_content)

  before_action :route_issue_chooser, only: %w(new choose), unless: -> { T.bind(self, IssuesReactHelper); is_issue_react_create_enabled? }
  before_action :discussion_can_be_converted, only: %w(new create)

  before_action :require_can_destroy, only: [:destroy]
  before_action :require_can_lock, only: [:lock]
  before_action :require_can_unlock, only: [:unlock]

  javascript_bundle :issues

  javascript_bundle :"structured-issues"

  T.unsafe(self).react_bundle_name = "issues-react"
  javascript_bundle :"issues-react", only: [:show, :dashboard], if: -> { T.bind(self, IssuesReactHelper); is_issue_react_dashboard_enabled? || (is_issue_dashboard_path? && is_pr_react_dashboard_enabled?) }
  javascript_bundle :"issues-react", only: [:index, :new, :choose], if: :is_issue_react_index_enabled?
  javascript_bundle :"issues-react", only: [:new, :choose], if: :is_issue_react_create_enabled?
  javascript_bundle :codespaces, only: [:show]

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:dashboard, :create]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:dashboard_react]

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
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:edit_form]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:redirect_to_scoped_org_dashboard]

  depends_on_clusters ApplicationRecord::Ballast,
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
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:show_title]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: false, only: [:choose, :new]

  depends_on_clusters ApplicationRecord::Spokes, optional: true, only: [:new]

  depends_on_clusters ApplicationRecord::Spokes, optional: false, only: [:choose]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    optional: true, only: [:choose, :new, :dashboard]

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
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:show_menu_content]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
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
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:show_from_project]

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
    optional: false, only: [:show_partial]

  depends_on_clusters ApplicationRecord::Ballast,
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
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:actions_menu]

  #      _              _
  #  ___| |_ ___  _ __ | |
  # / __| __/ _ \| '_ \| |
  # \__ \ || (_) | |_) |_|
  # |___/\__\___/| .__/(_)
  #              |_|
  # By adding a cluster to this list, you are asserting that the
  # Issue page should respond with a 500 error when that
  # cluster is unavailable. Those kinds of changes should not be
  # made without talking with the Issues team first.
  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:show]

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: true, only: [:show]

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:index]

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
    optional: true, only: [:index]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
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
    optional: false, only: [:dashboard]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:index_react]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:linked_closing_reference]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    optional: false, only: [:pr_review_status]

  depends_on_clusters ApplicationRecord::Memex,
    optional: true, only: [:index_react]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_from_project, :pr_review_status, :linked_closing_reference],
    optional: true

  # The following actions do not require conditional access checks, enforcement is done with custom behavior within each of these methods:
  # - dashboard: serves `/issues`, not consistently scoped to an organization.
  #   Enforcement may be required but should be done inline.
  # - redirect_to_scoped_org_dashboard: redirects to #dashboard, does not access
  #   protected organization resources before redirecting
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(dashboard redirect_to_scoped_org_dashboard pr_review_status)

  ISSUES_INDEX_TAG_FILTER_SYMBOLS = [:label, :milestone, :author, :assignee, :review, :project, :sort, :open, :closed]

  layout "repository"

  helper_method :render_layout?
  helper_method :render_repo_layout?
  helper_method :render_content?

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
    :issues_index_without_referer_limits, # rate limit requests to issues#index without referer header
  ]

  preload_features RATE_LIMITS_FEATURES

  DASHBOARD_FEATURES = [
    :issues_react,
    :new_pulls_dashboard,
    :pull_request_sub_triggers,
    :use_pull_request_subscriptions_enabled,
  ].freeze

  preload_features DASHBOARD_FEATURES, only: :dashboard

  SHOW_FEATURES = [
    :add_oauth_app_to_dog_tags,
    :author_association_internal_repository,
    :cap_filter_optimization,
    :cap_two_factor_filter,
    :emu_vss_business,
    :structured_issue_comment_templates,
    :slash_commands,
    :merge_queue,
    :merge_queue_extra_branch_protection_settings,
    :previewable_form_component,
    :access_warning,
    :issues_rate_limit_circuit_breaker,
    :extract_checklists,
    :tasklist_block,
    :tasklist_block_soft_limits,
    :tasklist_block_hard_limits,
    :tasklist_block_sync_check,
    :html_pipeline_bad_emoji,
    :issue_hierarchy_state,
    :issues_graph_api_disable_denormalized_read,
    :issues_graph_api_concurrent_faraday,
    :notifyd_enable_issue_thread_subscriptions,
    :notifyd_issue_watch_activity_notify,
    :notifyd_label_subscriptions,
    :notifyd_persistent_http_connection,
    :notifyd_only_assigned_push_notifications,
    :fuzzy_label_picker,
    :issue_summarization,
    :reactions_position,
    :convert_to_tasklist_block,
    :otel_rack_middleware,
    :issue_mention_filter_load_installation_for_source_repo,
    :notifications_async_issues_subscription_button,
    :notifications_async_watch_repo_button,
    :allow_internal_org_config_repo_if_public_repos_disabled, # Global health repo for EMU orgs
    :global_health_files_repository_loader_new_fetch_implementation, # Global health repo for EMU orgs
    :owner_scoped_github_apps,
    :check_missing_pull_request_on_issue_load,
    :graphql_preload_business_user_accounts,
    :graphql_memoize_actor_limiter,
    :issues_react_benchmark_graphql,
    :ghost_pilot_pr_autocomplete,
    :refactor_subject_actor_ids,
  ].freeze

  DEFAULT_FEATURES = [
    :authnd_experiment,
    :cpq_check,
    :copilot_conversational_ux_embedding_update,
    :copilot_conversational_ux_license_check,
    :gitrpc_always_include_request_id,
    :project_timeline_events,
    :stacks_toggle,
    :two_factor_checkup,
    :issues_service_mutative_actions_rate_limits,
    :tasklist_block_morpheus,
    :api_insights_rest,
    :permission_enforcer_with_caching,
    :add_oauth_app_to_dog_tags,
    :track_mobile_query_name,
    :skip_anon_jump_to_suggestions_enabled,
    :cap_pats_policy_enforcement,
  ]

  SHOW_WITH_REACT_FEATURES = SHOW_FEATURES + REACT_SERVER_SHOW_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHub::ClientSideFeatureFlags::FLAGS
  INDEX_WITH_REACT_FEATURES = REACT_SERVER_INDEX_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHub::ClientSideFeatureFlags::FLAGS
  CREATE_WITH_REACT_FEATURES = REACT_SERVER_CREATE_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHub::ClientSideFeatureFlags::FLAGS

  preload_features SHOW_WITH_REACT_FEATURES, only: [:show]
  preload_features INDEX_WITH_REACT_FEATURES + [:slash_commands, :owner_scoped_github_apps], only: :index
  preload_features CREATE_WITH_REACT_FEATURES, only: [:create, :choose, :new]
  preload_features DEFAULT_FEATURES

  preload_features [:load_issue_project_events_mysql], only: [:show]

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  rate_limit_requests \
    only: [:index],
    max: :issues_index_rate_limit_max,
    ttl: 1.minute,
    key: :issues_index_rate_limit_key,
    if: :issues_index_rate_limiting_enabled?,
    at_limit: :issues_index_rate_limit_at_limit

  rate_limit_requests \
    only: [:dashboard],
    max: ISSUES_DASHBOARD_WITHOUT_REFERER_RATE_LIMIT_MAX,
    ttl: 1.minute,
    key: :issues_dashboard_rate_limit_key,
    if: :issues_dashboard_without_referer_limits_enabled?,
    at_limit: :issues_dashboard_rate_limit_at_limit

  rate_limit_requests \
    only: [:create],
    max: :issues_create_rate_limit_max,
    ttl: 1.hour,
    key: :issues_create_rate_limit_key,
    log_key: :issues_create_rate_limit_log_key,
    at_limit: :issues_create_rate_limit_at_limit,
    if: :issues_create_or_service_rate_limits_enabled?

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if pulls_only? || (current_repository && current_issue && current_issue.pull_request?)
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  def index
    set_staff_tag
    self.pulls_only = index_flow.pulls_only unless GitHub.flipper[:issues_advanced_search].enabled?(current_user)

    if logged_in? && !pulls_only? && GitHub.flipper[:issues_react_benchmark_graphql].enabled?
      BenchmarkGraphqlJob.perform_later(current_user&.id, current_repository.id, nil)
    end


    # React handler used before the index_flow logic as the react app does not support these URLs yet
    # More in https://github.com/github/issues/issues/8269
    return if issue_react_index_handler(pulls_only: pulls_only?)

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

    respond_to do |format|
      format.html do
        track_time(tags: ["method:index", "step:render"]) do
          render "issues/index", locals: {
            issues: issues,
            pulls_only: pulls_only?,
            query: query,
            query_error: query_error,
            open_count: open_count,
            closed_count: closed_count,
            milestones_count: milestones_count,
            labels_count: labels_count,
            tags: query_parsed_search_tags,
            render_issue_react_opt_in: render_issue_react_index_opt_in?
          }
        end
      end
    end
  end

  def choose # rubocop:todo GitHub/UseRestfulActions
    set_staff_tag
    return if issue_react_choose_new_handler
    set_rails_tag

    respond_to do |format|
      format.html do
        render "issues/choose", locals: {
          issue_templates: !templates_available? ? nil : issue_templates,
          config: issue_templates_config,
          templates_available: templates_available?,
          render_issue_react_create_opt_in: render_issue_react_create_opt_in?,
        }
      end
    end
  end

  def dashboard # rubocop:todo GitHub/UseRestfulActions
    set_staff_tag

    T.unsafe(self.class).react_bundle_name = if is_pr_dashboard_path? && is_pr_react_dashboard_enabled?
      "pulls-dashboard"
    else
      "issues-react"
    end

    return if issue_react_dashboard_handler
    context_region_title pulls_only? ? "Pull Requests" : "Issues"
    current_organization = Organization.find_by_login(params[:user]) if params[:user]

    unless required_external_identity_session_present?(target: current_organization)
      render_external_identity_session_required(target: current_organization)
      return
    end

    flow = Issue::ControlFlow.new(
      params:       params,
      components:   parsed_issues_query,
      current_path: T.must(request).fullpath,
      current_user: current_user,
      exclude_archived: true,
    )
    query = flow.query
    self.pulls_only = flow.pulls_only

    self.parsed_issues_query = Search::Queries::IssueQuery.parse(query, current_user)

    return safe_redirect_to(flow.redirect_path) if flow.needs_redirection?
    tags = query_parsed_search_tags

    result = Issue::SearchResult.search(
      query:             parsed_issues_query,
      current_user:      current_user,
      remote_ip:         T.must(request).remote_ip,
      user_session:      user_session,
      page:              params[:page],
      tags:              tags,
      context:           "#{T.must(self.class.name).demodulize.underscore}-#{__method__}-#{pulls_only? ? "pull_requests" : "issues"}",
    )

    issues       = result[:issues]
    open_count   = result[:open_count]
    closed_count = result[:closed_count]

    if logged_in?
      GitHub.tracer.in_span("issues#dashboard prefills", kind: :internal) do |_span|
        IssuePrefiller.prefill(issues, current_user: current_user)
        if pulls_only?
          pull_requests = issues.map(&:pull_request).compact
          if pull_requests.any?
            PullRequest.prefill_associations(pull_requests, issues: issues)
            GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :base_branch_rule_evaluator)
            pull_requests.group_by(&:repository).each do |repo, repo_pull_requests|
              PullRequest.attach_statuses(repo, repo_pull_requests, with_check_runs: true)
            end
          end
        else
          set_rails_tag # set react tracking rails tag only if not pulls only and logged in (+ after redirections that happen above)
        end
      end
    end
    strip_analytics_query_string

    # Overwrite tags passed to datadog to facilitate filtering by controller and action
    # Log requests as controller: pull_requests, action: dashboard
    if T.must(request).path.start_with?("/pulls")
      GitHub::TaggingHelper.override_controller_tag(env: env, controller: "pull_requests")
    end

    render "issues/dashboard",
      layout: layout_for_turbo_request,
      locals: {
        issues: issues,
        query: query,
        pulls_only: pulls_only?,
        open_count: open_count,
        closed_count: closed_count,
        render_issue_react_dashboard_opt_in: render_issue_react_dashboard_opt_in?,
        applied_tab_filter_name: flow.applied_dashboard_tab_filter_name
      }
  end

  def show_title # rubocop:todo GitHub/UseRestfulActions
    issue = current_repository.issues.find_by_number(params[:id].to_i)

    return render_404 if render_not_found?(issue)
    set_headers_and_hovercard_subject(issue)

    respond_to do |format|
      format.json do
        render json: { title: issue.title }
      end
    end
  end

  def show
    @issue = current_issue
    return render_404 if render_not_found?(@issue)
    set_staff_tag

    if logged_in? && GitHub.flipper[:issues_react_benchmark_graphql].enabled?
      BenchmarkGraphqlJob.perform_later(current_user&.id, current_repository.id, @issue.number)
    end

    if @issue.pull_request?
      redirect_to show_pull_request_path(current_repository.owner, current_repository, current_issue)
      return
    end

    repo_without_issues = track_execution_time("repo_has_issues") do
      !current_repository.has_issues?
    end
    render_404 and return if repo_without_issues

    return if issue_react_show_handler
    set_rails_tag

    unless render_content?
      return render html: "{{ site_layout_content }}", layout: default_layout_or_override
    end

    set_headers_and_hovercard_subject(@issue)

    respond_to do |format|
      format.html do
        # Legacy issues/issue/xxx routes
        if params[:legacy] && params[:id]
          redirect_to issue_path(current_repository.owner, current_repository, current_issue), status: 301
          return
        end

        track_execution_time("mark_thread_as_read") do
          async_mark_thread_as_read @issue
        end

        issue_node = track_query_execution("show") do
          Issue::ShowLoader.issue_node(@issue, current_repository, current_user, pagination_params: { per_page: params[:timeline_per_page] }, cap_filter: cap_filter)
        end

        project_cards = ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_repository.organization) ? @issue.visible_cards_for(current_user).to_a : []
        #  tagging
        tags = %W[
          is_empty:#{project_cards.empty? && !@issue.has_timeline_items?}
          issue_unfurl:true]

        HierarchyCommands::CheckDatabaseSync.new(
          issue: issue_node.issue,
          repository: current_repository,
          viewer: current_user,
        ).call

        render "issues/show",
          layout: default_layout_or_override,
          locals: {
            issue_node: issue_node,
            project_cards: project_cards,
            tags: tags,
            tracking_issues: tracking_issues,
          }
      end
    end
  end

  def new
    set_staff_tag
    return if issue_react_choose_new_handler
    set_rails_tag

    fields = PrefilledIssueFields.new(
      params: params,
      repository: current_repository,
      user: current_user,
    )

    @issue = current_repository.issues.new
    @issue.title = fields.title
    @issue.body = fields.body
    @issue.memex_projects = fields.memex_projects
    @issue.projects = fields.projects
    @issue.milestone = fields.milestone
    @issue.assignees = fields.assignees
    @issue.body_template_name = fields.template
    issue_template = with_database_error_fallback(fallback: nil) { @issue.template }
    @issue.labels = fields.labels(user_can_label: @issue.labelable_by?(actor: current_user), allowed_labels: issue_template&.labels || [])
    @issue.structured_template_inputs = fields.structured_template_inputs
    issue_template&.track_required_inputs(action: :new)

    convert_from_task = params[:convert_from_task] && params[:convert_from_task] == "true"
    parent_issue = get_parent_issue(params[:parent_issue_number])
    created_from_discussion_number = params[:created_from_discussion_number]
    position = params[:position].present? ? params[:position] : nil
    click_type = params[:click_type]

    if convert_from_task && parent_issue && (click_type == "new_tab" || click_type == "current_tab")
      log_convert_to_issue_click_to_hydro(target_type: click_type, tracking_issue: parent_issue, title: @issue.title)
    end

    respond_to do |format|
      format.html do
        render "issues/new", locals: {
           convert_from_task: convert_from_task,
           parent_issue: parent_issue,
           position: position,
           created_from_discussion_number: created_from_discussion_number,
           warnings: fields.warnings,
           templates_available: templates_available?,
           render_issue_react_create_opt_in: render_issue_react_create_opt_in?,
        }
      end
    end
  end

  def create
    return if issue_create_handler

    if !logged_in? || blocked_by_owner?
      flash[:error] = "You can't perform that action at this time."
      redirect_to current_repository.permalink
      return
    end

    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    convert_from_task = params[:convert_from_task].present? && params[:convert_from_task] == "true"
    if convert_from_task && !current_user_can_push?
      if T.must(request).xhr?
        return render json: { text: "You don't have permissions to modify the issue." }, status: 401
      else
        parent_issue = get_parent_issue(params[:parent_issue_number])
        return redirect_to parent_issue.permalink
      end
    end

    saved = T.let(false, T.untyped)
    assignee_data = T.let({}, T.untyped)
    create_issue_orchestration = T.let(nil, T.untyped)

    track_time(tags: ["method:create", "step:build_issue"]) do
      new_params = indifferent_params.tap do |indifferent_params|
        assignee_data[:user_assignee_ids] = indifferent_params[:issue]&.delete(:user_assignee_ids)
        assignee_data[:assignee_id] = indifferent_params[:issue]&.delete(:assignee_id)
        assignee_data[:assignee] = indifferent_params[:issue]&.delete(:assignee)
      end
      assignee_data = assignee_data.compact
      @issue = build_issue new_params
    end

    if @issue.errors.empty?
      begin
        has_project_cards = @issue.cards.any?
        step = has_project_cards ? "step:save-with-project-cards" : "save"
        track_time(tags: ["method:create", "step:#{step}"]) do
          @issue.skip_create_issue_orchestration = true

          IssueOrchestration.transaction do
            saved = Issue.transaction do
              if has_project_cards
                ProjectCard.transaction do
                  @issue.save
                end
              else
                @issue.save
              end
            end

            if saved
              create_issue_orchestration = IssueOrchestration.create_issue!(actor: current_user, issue: @issue)
              create_issue_orchestration.data[:assignee_data] = assignee_data
              create_issue_orchestration.data[:options] = {
                skip_create_issue_orchestration: @issue.skip_create_issue_orchestration,
                skip_update_issue_orchestration: @issue.skip_update_issue_orchestration,
              }
            end
          end
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        GitHub.dogstats.increment("milestones.exceptions.locked_for_rebalance", { tags: ["context:issues_controller.create"] })
        flash.now[:error] = "Sorry! This milestone is temporarily locked for maintenance. Please try again."
      end
    end

    if saved
      create_issue_orchestration.execute! if create_issue_orchestration

      begin
        track_time(tags: ["method:create", "step:add_to_memex_projects"]) do
          @issue.add_to_memex_projects!(params[:issue_memex_project_ids], @issue, current_user)
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance, GitHub::Prioritizable::RebalanceRequiredError
        selected_project_count = (params[:issue_memex_project_ids] || {}).values.count { |v| v == "on" }
        GitHub.dogstats.increment("memex_project_items.exceptions.locked_for_rebalance", { tags: ["context:issues_controller.create"] })
        flash[:error] = "Sorry! We encountered an error and the issue was not added to the selected #{"project".pluralize(selected_project_count)}. Please try again."
      rescue MemexProjectItem::ProjectLimitReachedError => error
        GitHub.dogstats.increment("memex_project_items.exceptions.project_limit_reached", { tags: ["context:issues_controller.create"] })
        projects_with_errors_count = error.memex_projects_with_errors.count
        flash[:error] = "Sorry! We were unable to add the issue to the selected #{"project".pluralize(projects_with_errors_count)}. Projects cannot have more than #{error.memex_projects_with_errors.first&.items_limit} items."
      end
    end

    if saved && params[:created_from_discussion_number].present? && current_repository.discussions_on?
      track_time(tags: ["method:create", "step:created_from_discussion"]) do
        if @discussion.present?
          event = DiscussionEvent.new(discussion: @discussion, issue_id: @issue.id, actor: current_user,
            event_type: :created_issue)
          event.save
        end
      end
    end

    if saved
      track_time(tags: ["method:create", "step:instrumentation"]) do
        instrument_issue_creation_via_ui(@issue)
        instrument_saved_reply_use(params[:saved_reply_id], "issue")
      end

      if params[:enable_tip].present? && current_repository.organization
        OnboardingTasks::Organizations::AutoAssignIssue
        .new(taskable: current_repository.organization, user: current_user)
        .complete
      end

      path = issue_path(current_repository.owner, current_repository, @issue, enable_tip: params[:enable_tip].presence)

      if convert_from_task
        track_time(tags: ["method:create", "step:convert_from_task"]) do
          update_issue_body_after_convert_task(path)
        end

        if T.must(request).xhr?
          log_convert_to_issue_click_to_hydro(target_type: "inline", tracking_issue: current_issue, title: @issue.title, issue_id: @issue.id)
        end
      else
        redirect_to path
      end
    else
      if T.must(request).xhr? && convert_from_task
        render json: { text: "We are unable to convert the task to an issue at this time. Please try again." }, status: 422
      else
        fields = PrefilledIssueFields.new(
          params: params,
          repository: current_repository,
          user: current_user,
        )
        @issue.structured_template_inputs = fields.structured_template_inputs["issue_form"]

        @labels = current_repository.labels.order("name")
        render "issues/new"
      end
    end
  end

  # Bulk update a set of issues state, assignee, milestone or labels.
  #
  # PUT /github/github/issues/triage
  #
  # issues    - Array of Issue numbers or a String search query.
  # assignee  - A User ID to assign the issues to or blank to unassign.
  # milestone - A Milestone ID to set the issues to or black to unset.
  # labels    - A Hash of Label IDs with values '1' or "0" to add or remove.
  # state     - A string "open" or "closed" to assign to issues.
  # projects  - A Hash of Project IDs with values 'on' to add.
  def triage # rubocop:todo GitHub/UseRestfulActions
    case params[:issues]
    when String
      issues = Issue::SearchResult.search(
        query:             params[:issues],
        repo:              current_repository,
        current_user:      current_user,
        remote_ip:         T.must(request).remote_ip,
        tags:              default_search_tags,
        context:           "#{T.must(self.class.name).demodulize.underscore}-#{__method__}-#{pulls_only? ? "pull_requests" : "issues"}",
      )[:issues]
    when Array
      issues = current_repository.issues.where("issues.number IN (?)", params[:issues]).to_a
    else
      issues = []
    end

    unless current_repository.has_issues?
      issues = issues.select(&:pull_request?)
    end

    # copy over params for IssueTriageJob
    job_params = {}
    job_params[:state] = params[:state] if params.key?(:state)
    job_params[:milestone] = params[:milestone] if params.key?(:milestone)
    job_params[:assignee] = params[:assignee] if params.key?(:assignee)
    job_params[:clear_assignees] = params[:clear_assignees] if params.key?(:clear_assignees)

    if params[:assignees].respond_to?(:each)
      job_params[:assignees] = {}
      params[:assignees].each { |k, v| job_params[:assignees][k] = v }
    end

    if params[:labels].respond_to?(:each)
      job_params[:labels] = {}
      params[:labels].each { |k, v| job_params[:labels][k] = v }
    end

    if params[:projects].respond_to?(:each)
      job_params[:projects] = {}
      params[:projects].each { |k, v| job_params[:projects][k] = v }
    end

    status = JobStatus.create
    IssueTriageJob.perform_later(status.id, issues.map(&:id), T.must(current_user).id, job_params)

    if T.must(request).xhr?
      render json: { job: { url: job_status_url(status.id) } }
    else
      redirect_to :back
    end
  end

  VALID_SHOW_PARTIAL_TEMPLATES = [
    "issues/convert_to_discussion_dialog",
    "issues/form_actions",
    "issues/sidebar",
    "issues/sidebar/assignees_menu_content",
    "issues/sidebar/labels_menu_content",
    "issues/sidebar/milestone_menu_content",
    "issues/sidebar/new/assignees",
    "issues/sidebar/new/labels",
    "issues/sidebar/new/milestone",
    "issues/sidebar/project_card_move",
    "issues/sidebar/projects_menu_content",
    "issues/sidebar/show/assignees", # Only used in test?
    "issues/sidebar/show/labels",
    "issues/sidebar/show/milestone",
    "issues/state_button_wrapper",
    "issues/timeline",
    "issues/title",
    "projects/card_issue_details_title",
    "projects/card_issue_details_title_icon",
    # For splitting pull requests live updates
    "pull_requests/sidebar/show/reviewers",
  ]

  def show_partial # rubocop:todo GitHub/UseRestfulActions
    partial = params[:partial]
    # Since we have renamed `projects_menu_content_fast` to `projects_menu_content` we need to check both as existing sessions may use both.
    partial = "issues/sidebar/projects_menu_content" if partial == "issues/sidebar/projects_menu_content_fast"

    return head :not_found unless VALID_SHOW_PARTIAL_TEMPLATES.include?(partial)

    milestone_partial = "issues/sidebar/new/milestone"
    if T.must(request).post? && milestone_partial == partial && params[:milestone] == "new"
      params[:milestone] = create_milestone(params[:milestone_title])
    end

    track_time(tags: ["method:show_partial", "partial:#{partial}", "step:build_issue"]) do
      @issue = params[:id] ? current_issue : build_issue(indifferent_params)
    end

    track_time(tags: ["method:show_partial", "partial:#{partial}", "step:render"]) do
      return head :not_found if @issue.nil?
      return head :not_found unless @issue.new_record? || @issue.pull_request? || current_repository.has_issues?

      respond_to do |format|
        format.html do
          locals = {
            issue: @issue,
            deferred_content: false,
            inline: params[:inline] == "true",
            sticky: params[:sticky] == "true"
          }

          if partial == "issues/sidebar/project_card_move"
            # The show_columns_menu param can be passed to override the show_columns_menu local being made true by default.
            # Passing false prevents showing the caret for the column dropdown in the projects sidebar.
            # Currently limited to issues/sidebar/project_card_move partial and others will need to be added to this list to use it.
            show_columns_menu = true unless params.has_key?(:show_columns_menu) && params[:show_columns_menu] != "true"
            locals = locals.merge({ show_columns_menu: show_columns_menu })
          end

          if partial == "issues/title"
            if current_repository&.owner&.feature_enabled?(:tasklist_block)
              locals[:tasklist_block_enabled] = true
            end

            if current_repository&.owner&.feature_enabled?(:convert_to_tasklist_block)
              locals[:convert_to_tasklist_block_enabled] = true
            end

            locals[:tracking_issues] = tracking_issues
          end

          if partial == "issues/checklist_progress"
            locals[:render_mode] = params[:render_mode]
          end

          if partial == "issues/convert_to_discussion_dialog"
            locals[:discussion_categories] = current_repository.available_discussion_categories
          end

          if partial == "issues/sidebar/labels_menu_content"
            locals[:use_label_typeahead] = current_repository&.feature_enabled?(:issues_labels_typeahead)
          end

          if partial == "issues/sidebar/projects_menu_content" && params[:tasklist_id]
            locals[:project_picker_result_id] = "project-picker-results-#{params[:tasklist_id]}-#{current_repository.name}-#{current_issue.number}"
          end

          if partial == "pull_requests/sidebar/show/reviewers"
            locals[:pull_request] = @issue.pull_request
          end

          # rubocop:disable GitHub/RailsControllerRenderLiteral
          if force_layout?
            # update the partial path to include a _ and match the actual file on disk
            # so that issues/sidebar/assignees_menu_content becomes issues/sidebar/_assignees_menu_content
            # this is needed because we need to render with "render partial" instead of "render partial: partial"
            # to enable site layout
            partial = File.dirname(partial) + "/_" + File.basename(partial)
            # render partial with the layout, useful for debugging performance issues using the staffbar
            render partial, object: @issue, locals: locals, layout: true
          else
            render partial: partial, object: @issue, locals: locals
          end
        end

        format.json do
          if partial == "issues/sidebar/labels_menu_content"
            timer = Timer.start
            type_ahead_enabled = params[:typeAhead].present?

            if type_ahead_enabled
              search_query = params[:q].to_s
              sanitized_query = ActiveRecord::Base.sanitize_sql_like(search_query)

              sorted_labels = current_repository.sorted_labels_containing_keyword(issue_or_pr: @issue, contains: sanitized_query)
            else
              sorted_labels = current_repository.sorted_labels(issue_or_pr: @issue, cache_label_html: true)

              # If this code path gets hit, it means we've pre-rendered labels already so don't need to return it.
              sorted_labels = sorted_labels - @issue.labels
            end

            output = sorted_labels.map do |label|
              {
                id: label.id,
                name: label.name,
                color: label.color,
                htmlName: label.name_html,
                selected: @issue.labels.include?(label),
                description: label.description
              }
            end

            render json: { labels: output }
            output
          elsif "issues/sidebar/assignees_menu_content" == partial
            if GitHub.flipper[:filter_assignee_suggestions_for_viewer].enabled?(current_user)
              return head :not_found unless @issue.triageable_by?(current_user)
            end

            timer = Timer.start
            sorted_assignees = []
            type_ahead_enabled = params[:typeAhead].present?
            # If type-ahead header isn't present, we assume the front-end JS isn't updated yet, so we
            # assume old behaviour and fall-back.
            if type_ahead_enabled
              search_query = params[:q].to_s

              if search_query.blank?
                return render json: { users: [] }
              else
                sorted_assignees = @issue.filtered_assignees_list(current_user, search_query)
              end
              sorted_assignees.delete(current_user)

              # Participants isn't guaranteed to be correct, in the event of PR#New, this doesn't populate with assignees
              # So we need to filter both to ensure we aren't returning duplicated results.
              sorted_assignees = sorted_assignees - @issue.participants - @issue.assignees
            else
              sorted_assignees = @issue.sorted_assignees_list(current_user: current_user)

              # If this code path gets hit, it means we've pre-rendered the assignees already so don't need to return it.
              sorted_assignees = sorted_assignees - @issue.assignees
            end

            user_data = track_time(metric: "assignees.prepare_users.dist.time") do
              sorted_assignees.map do |user|
                profile_name = user.safe_profile_name
                user_status = user.user_status
                if !user_status&.expired? && user_status&.limited_availability?
                  profile_name = "#{profile_name} (busy)"
                end

                {
                  id: user.id,
                  name: profile_name,
                  login: user.display_login_legacy,
                  selected: @issue.assigned_to?(user),
                  avatar: user.primary_avatar_url(60),
                  class: helpers.avatar_class_names(user),
                }
              end
            end

            output = track_time(metric: "assignees.render.dist.time", tags: []) do
              render json: { users: user_data }
            end

            timer.stop
            tags = ["type_ahead_enabled:#{type_ahead_enabled}"]

            GitHub.dogstats.distribution("issues_controller.assignees_menu_content.dist.time", timer.elapsed_ms, tags: tags)

            output
          else
            head :bad_request
          end
        end
      end
    end
  end

  VALID_SHOW_MENU_CONTENT_TEMPLATES = [
    "issues/filters/assigns_content",
    "issues/filters/authors_content",
    "issues/filters/labels_content",
    "issues/filters/milestones_content",
    "issues/filters/orgs_content",
    "issues/filters/projects_content",
    "issues/triage/actions_content",
    "issues/triage/assigns_content",
    "issues/triage/labels_content",
    "issues/triage/projects_content",
    "issues/triage/milestones_content",
  ].freeze

  def show_menu_content # rubocop:todo GitHub/UseRestfulActions
    partial = params[:partial]
    authorization_required if current_repository

    return head :not_found unless VALID_SHOW_MENU_CONTENT_TEMPLATES.include?(partial)

    track_time(metric: "view.dist.time", tags: ["subject:issue", "action:show_partial_render"]) do
      respond_to do |format|
        format.html do
          case partial
          when "issues/filters/assigns_content"
            query = params_or_default_query_string
            render partial: "issues/filters/assigns_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/filters/authors_content"
            query = params_or_default_query_string
            render partial: "issues/filters/authors_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/filters/labels_content"
            query = params_or_default_query_string
            render partial: "issues/filters/labels_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/filters/milestones_content"
            query = params_or_default_query_string
            render partial: "issues/filters/milestones_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/filters/orgs_content"
            query = params_or_default_query_string
            render partial: "issues/filters/orgs_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/filters/projects_content"
            query = params_or_default_query_string
            render partial: "issues/filters/projects_content", layout: false, locals: {
              issue: @issue,
              query: query,
              pulls_only: pulls_only?,
            }
          when "issues/triage/actions_content"
            render partial: "issues/triage/actions_content", layout: false
          when "issues/triage/assigns_content"
            render partial: "issues/triage/assigns_content", layout: false
          when "issues/triage/labels_content"
            render partial: "issues/triage/labels_content", layout: false
          when "issues/triage/projects_content"
            render partial: "issues/triage/projects_content", layout: false
          when "issues/triage/milestones_content"
            render partial: "issues/triage/milestones_content", layout: false
          end
        end
      end
    end
  end

  def unmark_as_duplicate # rubocop:todo GitHub/UseRestfulActions
    # TODO: (katallaxie) remove after unread timeline has been moved
    # We have to do a reverse look up for PRs, because global ids for PRs use numbers, and for issues they use ids.
    # Duplicate issues is masking to Issues, that is why we have to do an extra lookup to find the underlying issue.
    type_name, id = Platform::Helpers::NodeIdentification.from_global_id(params[:issue_id])
    if type_name == "PullRequest"
      id = current_repository.pull_requests.find_by(id: id)&.issue&.id
    end

    duplicate_issue = DuplicateIssue.with_duplicate_issue(current_issue.id)
      .with_canonical_issue(id).first

    success = if duplicate_issue.nil?
      head :not_found and return
    elsif duplicate_issue.duplicate?
      head :forbidden and return unless duplicate_issue.can_unmark_as_duplicate?(current_user)
      event = current_issue.events.unmarked_as_duplicates.
            build(actor_id: T.must(current_user).id, repository_id: current_repository.id,
                  subject_type: "Issue", subject_id: id)

      duplicate_issue.actor = current_user
      duplicate_issue.duplicate = false

      event.save && duplicate_issue.save

      head :ok and return
    else
      head :ok and return
    end
  end

  def update
    return head 200 unless logged_in? && !blocked_by_owner?
    original_unsafe_params = indifferent_params

    if params[:pull_request]
      unsafe_params = original_unsafe_params[:pull_request]
    else
      unsafe_params = original_unsafe_params.fetch :issue, {}
    end

    unsafe_params.merge(body: params[:comment]) if params[:comment]
    safe_issue_params = unsafe_params.slice(
      :milestone_id,
      :title,
      :body,
    )

    valid = T.let(true, T.untyped)
    text = T.let(nil, T.untyped)
    issue = current_issue
    issue.skip_hydro_update_event_instrumentation = true
    previous_title = issue.title
    previous_body = issue.body
    update_issue_orchestration = T.let(nil, T.untyped)

    # prevent updates from stale data
    if stale_model?(current_issue)
      return render_stale_error(model: current_issue, error: "Could not edit issue. Please try again.", path: issue_path(current_issue))
    end

    if current_user_can_push? && safe_issue_params[:milestone_id] == "clear"
      safe_issue_params[:milestone_id] = nil
    else
      safe_issue_params.delete(:milestone_id)
    end

    issue.skip_create_issue_orchestration = true
    issue.skip_update_issue_orchestration = true

    IssueOrchestration.transaction do
      issue_params_except_body = safe_issue_params.except(:body)
      valid = issue_params_except_body.empty? || issue.update(issue_params_except_body)

      async_mark_thread_as_read issue

      if operation = TaskListOperation.from(params[:task_list_operation])
        text = operation.call(issue.body)
        valid = issue.update_body(text, current_user) if text
      elsif operation = TasklistBlocks::Operation.from(params[:tasklist_blocks_operation], current_user: current_user, current_repository: current_repository)
        cache_enabled = GitHub.flipper[:hierarchy_cache_key].enabled?
        GitHub.dogstats.distribution_time("tasklist_blocks.operation.dist", tags: ["cache_enabled:#{cache_enabled}"]) do
          body = safe_issue_params[:body] || current_issue.body
          if operation.instance_of?(TasklistBlocks::Operations::ConvertToIssue)
            text = with_primary_repository_cluster { operation.call(body) }
          else
            text = operation.call(body)
          end
          valid = issue.update_body(text, current_user) if text
        end

        instrument_tasklist_block_operation(operation: operation, actor: current_user, repository: current_repository, issue: issue)
      elsif safe_issue_params[:body]
        valid = issue.update_body(safe_issue_params[:body], current_user)
      end

      if valid
        update_issue_orchestration = IssueOrchestration.update_issue!(actor: current_user, issue: issue)
        update_issue_orchestration.data[:options] = {
          skip_create_issue_orchestration: issue.skip_create_issue_orchestration,
          skip_update_issue_orchestration: issue.skip_update_issue_orchestration,
        }
      end
    end

    if params[:tasklist_blocks_operation_tracker]
      operation_array = JSON.parse(params[:tasklist_blocks_operation_tracker])
      instrument_tasklist_block_md_to_ui_operation(operations: operation_array, actor: current_user, repository: current_repository, issue: issue)
    end

    if valid
      update_issue_orchestration.execute! if update_issue_orchestration

      issue.instrument_hydro_update_event(
        previous_title: previous_title,
        previous_body: previous_body,
      )
      track_issue_edits_from_project_board(edited_fields: safe_issue_params.keys)
    end

    if T.must(request).xhr?
      respond_to do |format|
        format.json do
          if valid
            errors = issue.errors.map { |error| error.message }
            render json: issue_update_payload(issue.reload, errors)
          else
            render json: { errors: issue.errors.full_messages }, status: :unprocessable_entity
          end
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to issue_path(issue) }
      end
    end
  end

  def destroy
    # verify delete because of: https://github.com/github/github/issues/103421
    return render_404 unless params[:verify_delete] == "1"

    o = IssueOrchestration.delete_issue(issue: current_issue, actor: current_user)
    begin
      o.execute
    rescue ActiveRecord::RecordNotDestroyed
      flash[:error] = "Issue could not be deleted"
      redirect_to :back
      return
    end

    respond_to do |format|
      format.json { head :ok }
      format.html do
        flash[:notice] = "The issue was successfully deleted."
        if params[:redirect_url]
          safe_redirect_to params[:redirect_url]
        else
          redirect_to issues_path
        end
      end
    end
  end

  # Sets the milestone for one or many issues.
  #
  # Expected params:
  #
  #   :milestone - The Milestone's id you wish to set. Optionally "clear" if
  #                you wish to clear the current milestones.
  #   :new_milestone - A title of a new milestone to create.
  #   :issues - An Array of Issue numbers.
  #
  # If :new_milestone is sent, :milestone is ignored and a *new* milestone
  # is created (without a due date) and the issue(s) are assigned to the new
  # milestone.
  #
  # For AJAX requests, JSON is returned with the HTML of the infobar and
  # context pane partials.
  def set_milestone # rubocop:todo GitHub/UseRestfulActions
    if params[:milestone] == "new"
      milestone = create_milestone(params[:milestone_title])
      return head :unprocessable_entity unless milestone
    elsif params[:milestone] == "clear"
      milestone = nil
    else
      milestone = current_repository.milestones.find(params[:milestone])
    end

    issue = current_issue
    if issue.milestone != milestone
      begin
        Issue.transaction do
          issue.milestone = milestone
          issue.save!
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        GitHub.dogstats.increment("milestones.exceptions.locked_for_rebalance", { tags: ["context:issues_controller.set_milestone"] })
        return render status: 503, plain: "Sorry! This milestone is temporarily locked for maintenance. Please try again."
      end
    end

    @issue = issue
    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/show/milestone", locals: { issue: issue }
      end
    end
  end

  def create_milestone(title) # rubocop:todo GitHub/UseRestfulActions
    return unless current_user_can_push?
    return unless title

    milestone = current_repository.milestones.build(title: title)
    milestone.created_by = current_user
    return milestone if milestone.save
  end

  # Public: Locks an issue publicly with a reason to not to comment to.
  def lock # rubocop:todo GitHub/UseRestfulActions
    reason = params[:reason].present? ? params[:reason] : nil

    unless current_issue.locked?
      current_issue.lock(current_user, reason)
    end
    redirect_to :back
  end

  # Public: Unlocks an issue publicly, this needs no reason.
  def unlock # rubocop:todo GitHub/UseRestfulActions
    if current_issue.locked?
      current_issue.unlock(current_user)
    end
    redirect_to :back
  end

  def convert_to_discussion # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository&.discussions_active?

    unless current_issue.can_be_converted_by?(current_user)
      flash[:error] = "You cannot convert that issue to a discussion at this time."
      return redirect_to(issue_path(current_issue))
    end

    category = if params[:category_id]
      current_repository.discussion_categories.find_by(id: params[:category_id])
    end

    converter = IssueToDiscussionConverter.new(current_issue, actor: current_user, category: category)

    unless converter.prepare_for_conversion
      message = "Unable to convert this issue to a discussion. "
      if converter.discussion
        message += converter.discussion.errors.full_messages.to_sentence
      else
        message += current_issue.errors.full_messages.to_sentence
      end
      flash[:error] = message
      return redirect_to(issue_path(current_issue))
    end

    ConvertToDiscussionJob.perform_later(current_user, converter.discussion,
      converter.issue_originally_open)

    redirect_to discussion_path(converter.discussion, current_repository, converting: "1")
  end

  def linked_closing_reference # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_issue

    close_issue_references = CloseIssueReference.viewable_for(viewer: current_user, issue: current_issue)

    return render_404 unless close_issue_references.size == 1

    if current_issue.pull_request?
      issue = close_issue_references.first.issue
      GlobalInstrumenter.instrument("browser.issue_cross_references.click",
                                    reference_location: params[:reference_location],
                                    user_id: current_user,
                                    issue_id: issue.id,
                                    pull_request_id: current_issue.pull_request_id)

      redirect_to issue_path(issue)
    else
      pr = close_issue_references.first.pull_request
      GlobalInstrumenter.instrument("browser.issue_cross_references.click",
                                    reference_location: params[:reference_location],
                                    user_id: current_user,
                                    issue_id: current_issue.id,
                                    pull_request_id: pr.id)

      redirect_to pull_request_path(pr)
    end
  end

  def redirect_to_scoped_org_dashboard # rubocop:todo GitHub/UseRestfulActions
    if org = Organization.where(login: params[:org]).first
      route = pulls_only? ? all_pulls_path(user: org) : all_issues_path(user: org)
      redirect_to route
    else
      route = pulls_only? ? all_pulls_path : all_issues_path
      redirect_to route
    end
  end

  def show_from_project # rubocop:todo GitHub/UseRestfulActions
    render_404 and return if current_issue.spammy?
    issue_node = Issue::Loader::Project.issue_node(current_issue, current_repository, current_user, cap_filter: cap_filter)

    respond_to do |format|
      format.html do
        render partial: "projects/card_issue_details", locals: { issue: current_issue, issue_node: issue_node }
      end
    end
  end

  def dismiss_first_contribution_prompt # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_issue.show_first_contribution_prompt?(current_user)
    current_issue.dismiss_first_contribution_prompt
    head :ok
  end

  def dismiss_first_contribution_prompt_and_redirect # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_issue.show_first_contribution_prompt?(current_user)
    current_issue.dismiss_first_contribution_prompt
    redirect_to community_path
  end

  def pr_review_status # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_issue.pull_request?
    return render_404 if current_issue.hide_from_user?(current_user)
    return render_404 unless current_issue.readable_by?(current_user)

    # If we're not SSO'd for the issue, don't render anything
    owner = current_issue.repository.owner
    if owner.organization? && !required_external_identity_session_present?(target: owner)
      return render_404
    end

    render partial: "pull_requests/review_status", locals: { pull_request: current_issue.pull_request }
  end

  def actions_menu # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?
    return render_404 unless current_issue

    current_issue.preload_viewer_attributes(current_user)

    render partial: "comments/comment_header_details_menu", locals: {
      comment: current_issue,
      viewer: current_user,
      repository: current_repository,
      form_path: issue_comment_path(
        current_issue.repository.owner.display_login,
        current_issue.repository.name,
        current_issue.id
      ),
      issue_path: issue_path(
        current_repository.owner,
        current_repository,
        current_issue),
      href: params[:href]
    }
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?
    unless current_issue.editable_by?(current_user)
      head :forbidden
      return
    end

    render Comments::EditForm::EditFormComponent.new(
      comment: current_issue,
      comment_context: params[:comment_context],
      textarea_id: params[:textarea_id],
      slash_commands_enabled: T.must(current_user).slash_commands_enabled?,
      slash_commands_surface: current_issue.pull_request? ? SlashCommands::PULL_REQUEST_BODY_SURFACE : SlashCommands::ISSUE_BODY_SURFACE,
      tasklist_blocks_enabled: current_repository&.owner&.feature_enabled?(:tasklist_block),
      current_repository: current_repository
    ), layout: false
  end

  def summary # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?
    return render_404 unless T.must(current_user).feature_enabled?(:issue_summarization)

    render "issues/sidebar/show/summary", locals: {
      issue: current_issue
    }, layout: false
  end

  private

  def require_can_unmark_duplicate
    render_404 unless current_issue.can_mark_as_duplicate?(current_user)
  end

  def require_can_destroy
    render_404 unless current_issue.deleteable_by?(current_user)
  end

  # Private: Checks if the viewer can lock the current issue.
  def require_can_lock
    redirect_to :back unless current_issue.lockable_by?(current_user)
  end

  # Private: Checks if the viewer can unlock the current issue.
  def require_can_unlock
    redirect_to :back unless current_issue.unlockable_by?(current_user)
  end

  def set_milestone_permission_required
    render_404 unless current_issue.can_set_milestone?(current_user)
  end

  def indifferent_params
    params.permit!.to_h.with_indifferent_access
  end

  def structured_issue_body
    params[:issue][:body].permit!.to_h.map do |id, response|
      next if id.start_with?("label.") || id == TemplatableContent::TEMPLATE_PATH_KEY

      label = params[:issue][:body]["label.#{id}"] || id
      "### #{label}\n\n#{response}"
    end.compact.join("\n\n")
  end

  # We are overriding RepositoryControllerMethods#current_repository in order to
  # introduce strict_loading to help identify any n+1s during the removal of GraphQL in Issues#show views
  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    if is_issues_react_show_enabled? && owner && params[:repository].present?
      includes = [
        :network_privilege,
      ]
      includes << :tabs if GitHub.custom_tabs_enabled?
      repo = owner.find_repo_by_name(
        params[:repository],
        strict_loading: true,
        includes: includes
      )

      @current_repository = repo
      return repo
    end

    @current_repository = if use_strict_loading && owner && params[:repository].present?
      includes = [
        :network,
        :network_privilege,
        :mirror,
        :repo_interaction_limit,
        open_graph_image: [:repository]
      ]
      includes << :tabs if GitHub.custom_tabs_enabled?

      repo = owner.find_repo_by_name(params[:repository], strict_loading: use_strict_loading, includes: includes)

      with_database_error_fallback do
        GitHub::PrefillAssociations.prefill_associations(repo, :memex_project_links)
      end

      repo
    else
      with_replica_repository_cluster { super }
    end
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

  # A filter to check whether you have permission to modify this issue or group
  # of issues.
  #
  # Redirects away unless you have access.
  def issue_modifiers_only
    return redirect_to_login unless logged_in?
    return redirect_to "/" unless current_repository

    allowed = if current_issue
      current_issue.editable_by?(current_user)
    else
      current_user_can_push?
    end

    redirect_to "/" unless allowed
  end

  def populate_assignees
    if current_repository
      users = current_repository.visible_available_assignees_for(current_user).limit(GitHub.assignees_list_limit).to_a || []

      users.sort! { |a, b| a.display_login.downcase <=> b.display_login.downcase }

      if logged_in?
        users.delete(current_user)
        users.unshift(current_user)
      end

      users
    else
      [current_user]
    end
  end
  helper_method :populate_assignees

  def populate_authors
    if current_repository
      users = populate_assignees
      installations = IntegrationInstallation.with_repository(current_repository).includes(integration: :bot)
      bots = installations.map(&:integration).compact.map(&:bot)
      users.concat(bots)

      users.sort! { |a, b| a.display_login.downcase <=> b.display_login.downcase }

      if logged_in?
        users.delete(current_user)
        users.unshift(current_user)
      end

      users
    else
      [current_user]
    end
  end
  helper_method :populate_authors

  def repo_issues_required
    if  !params[:pulls_only] && !current_repository.has_issues?
      render_404
    end
  end

  def enabled_new_issues_required
    if !current_repository.has_issues? || current_repository.archived?
      render_404
    end
  end

  def issue_required
    if current_issue.nil?
      render_404
    end
  end

  def content_authorization_required
    authorize_content(:issue, repo: current_repository)
  end

  def index_flow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @index_flow ||= Issue::ControlFlow.new(
      params: params,
      repo:   current_repository,
      components: parsed_issues_query,
      current_user: current_user,
      current_path: T.must(request).fullpath,
    )
  end

  def route_supports_advisory_workspaces?
    return true if current_issue&.pull_request?
    partial = params[:partial]
    if action_name == "show_partial"
      assignee_partials = ["issues/sidebar/assignees_menu_content", "issues/sidebar/new/assignees"]
      return true if assignee_partials.include?(partial)
    elsif action_name == "show_menu_content"
      return true if ["issues/filters/authors_content", "issues/filters/assigns_content"].include?(partial)
    end
    return false if action_name != "index"
    index_flow.pulls_only
  end

  # Determine if we should direct users toward the issue template picker (/new/choose)
  # or straight to a blank issue (/new)
  def route_issue_chooser
    if redirect_to_blank_issue?
      safe_new_issue_params = indifferent_params.slice(:permalink, :milestone)
      redirect_to new_issue_path(current_repository.owner, current_repository, params: safe_new_issue_params)
    elsif redirect_to_issue_template_picker?
      safe_new_issue_params = indifferent_params.slice(:permalink, :milestone)
      redirect_to choose_issue_path(current_repository.owner, current_repository, params: safe_new_issue_params)
    end
  end

  # Returns a boolean value indicating whether there are any preferred issue templates available for the current repository.
  #
  # @return [Boolean] `true` if there are preferred issue templates available, `false` otherwise.
  # When returning false, this means that most probably templates are not accissible because of database problems.
  def templates_available?
    issue_templates != :unknown
  end

  # Discussions with the polls category can't be converted to issues.
  # https://github.com/github/discussions/issues/1658
  def discussion_can_be_converted
    return unless params[:created_from_discussion_number]
    @discussion = Discussion.find_by(repository_id: current_repository.id, number: params[:created_from_discussion_number].to_i)

    if @discussion && @discussion.poll.present?
      flash[:error] = "Discussion with polls can't be converted to issue."
      redirect_to discussion_path(@discussion)
    end
  end

  def redirect_to_blank_issue?
    return false unless action_name == "choose"
    return true if !templates_available? || !(issue_templates.valid_templates.any? || issue_templates_config&.contact_links.present?)
    false
  end

  def redirect_to_issue_template_picker?
    return false unless action_name == "new"
    return false if !templates_available? || accessing_issue_template?
    issue_templates.valid_yaml_templates.any? && !issue_templates_config.blank_issues_enabled? && !current_repository.writable_by?(current_user)
  end

  def issue_templates # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    with_database_error_fallback(fallback: :unknown) do
      current_repository.preferred_issue_templates
    end
  end

  def issue_templates_config # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @issue_templates_config if defined?(@issue_templates_config)
    unless issue_templates == :unknown
      @issue_templates_config = issue_templates.issue_template_config
    end
  end

  def accessing_issue_template?
    params[:template] && issue_templates.valid_templates.map(&:filename).include?(params[:template])
  end

  # opt-out of IP allow list
  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  # opt-out of SAML
  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    true
  end

  # opt-out of 2FA
  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def default_layout_or_override
    render_layout? ? :default : false
  end

  def update_issue_body_after_convert_task(path)
    position = params[:position].split(",").map(&:to_i).compact
    parent_issue = get_parent_issue(params[:parent_issue_number]) || current_issue

    if parent_issue&.update_issue_body_after_convert_task(position, @issue, current_user)
      if T.must(request).xhr?
        render json: { title: @issue.title, url: path }
      else
        redirect_to path
      end
    else
      error_text = "The issue was successfully created but we are unable to update the original comment at this time."
      if T.must(request).xhr?
        render json: { text: error_text, url: path, url_title: "#{current_repository}##{@issue.number}" }, status: 422
      else
        flash[:error] = error_text
        redirect_to path
      end
    end
  end

  def get_parent_issue(parent_issue_number)
    parent_issue = parent_issue_number && current_repository.issues.find_by_number(parent_issue_number.to_i)
    return nil unless parent_issue && parent_issue.readable_by?(current_user) && !parent_issue.hide_from_user?(current_user)
    parent_issue
  end

  def log_convert_to_issue_click_to_hydro(target_type:, tracking_issue:, title:, issue_id: nil)
    if templates_available?
      GlobalInstrumenter.instrument(
        "browser.convert_task_to_issue.click",
        {
          user_id: current_user,
          target_type: target_type,
          repository: current_repository,
          repository_owner: current_repository.owner,
          tracking_issue: tracking_issue,
          title: title,
          issue_id: issue_id,
        },
      )
    end
  end

  def defer_status_check_rollups?
    true
  end

  def defer_commit_badges?
    true
  end

  # Private: queries for tracking issues associated with the given issue, if the feature is enabled
  #
  # Returns an array of tracking issue hashes
  def tracking_issues
    return [] unless tracking_issues_enabled?
    return [] unless @issue

    @issue.normalized_tracking_issues(
      viewer: current_user,
      cap_filter: cap_filter,
    )
  end

  def tracking_issues_enabled?
    !GitHub.enterprise? || current_repository&.owner&.feature_enabled?(:tasklist_block)
  end
end
