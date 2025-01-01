# typed: true
# frozen_string_literal: true

require "typhoeus"
require "typhoeus/adapters/faraday"

class IssuesController < AbstractRepositoryController
  include ShowPartial
  include LabelEducationHelper
  include IssuesHelper
  include TimelineHelper
  include CommentsHelper
  include HierarchyHelper
  include IssuesReactHelper
  include GitHub::RateLimitedRequest
  include ControllerMethods::Codespaces
  include ControllerMethods::Issues
  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency
  include ResilienceHelper

  around_action :track_and_report_render_view_time, only: [:show]
  around_action :track_and_report_graphql_executions, only: [:show]
  around_action :track_and_report_mysql_executions, only: [:show]
  before_action :enabled_new_issues_required, only: %w(new)
  before_action :repo_issues_required, only: %w(choose)
  before_action :login_required,
    except: %w(index new choose show)
  before_action :login_required_redirect_for_public_repo, only: [:new, :choose]
  before_action :writable_repository_required,
    except: %w(index dashboard show
               redirect_to_scoped_org_dashboard)
  before_action :content_authorization_required, only: %w(new)
  before_action :handle_issue_transfer_deletion_or_conversion, only: [:show]
  skip_before_action :cap_pagination, unless: :robot?
  skip_before_action :authorization_required, only: %w(dashboard redirect_to_scoped_org_dashboard)

  before_action :discussion_can_be_converted, only: %w(new)

  before_action :external_identity_session_required, only: [:new, :index, :show]

  javascript_bundle :"structured-issues"
  javascript_bundle :"issues-react", only: [:show, :dashboard], if: -> { T.bind(self, IssuesReactHelper); is_issue_dashboard_path? }
  javascript_bundle :"issues-react", only: [:index, :new, :choose]

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:dashboard]

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
    ApplicationRecord::Permissions,
    optional: true, only: [:choose, :new, :dashboard]

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
    ApplicationRecord::Pages,
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
    ApplicationRecord::Pages,
    optional: false, only: [:dashboard]


  # The following actions do not require conditional access checks, enforcement is done with custom behavior within each of these methods:
  # - dashboard: serves `/issues`, not consistently scoped to an organization.
  #   Enforcement may be required but should be done inline.
  # - redirect_to_scoped_org_dashboard: redirects to #dashboard, does not access
  #   protected organization resources before redirecting
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(dashboard redirect_to_scoped_org_dashboard)

  layout "repository"

  helper_method :render_layout?
  helper_method :render_repo_layout?

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
    :issues_index_without_referer_limits, # rate limit requests to issues#index without referer header
  ]

  preload_features RATE_LIMITS_FEATURES

  DASHBOARD_FEATURES = [
    :pull_request_sub_triggers,
    :use_pull_request_subscriptions_enabled,
    :pull_request_single_subscription,
  ].freeze

  preload_features DASHBOARD_FEATURES, only: :dashboard

  SHOW_FEATURES = [
    :add_oauth_app_to_dog_tags,
    :cap_filter_optimization,
    :cap_two_factor_filter,
    :emu_vss_business,
    :structured_issue_comment_templates,
    :slash_commands,
    :merge_queue,
    :merge_queue_extra_branch_protection_settings,
    :previewable_form_component,
    :issues_rate_limit_circuit_breaker,
    :tasklist_block,
    :tasklist_block_soft_limits,
    :tasklist_block_hard_limits,
    :tasklist_block_sync_check,
    :issues_graph_api_deprecated,
    :html_pipeline_bad_emoji,
    :issue_hierarchy_state,
    :issues_graph_api_disable_denormalized_read,
    :issues_graph_api_concurrent_faraday,
    :notifyd_enable_issue_thread_subscriptions,
    :notifyd_issue_watch_activity_notify,
    :notifyd_label_subscriptions,
    :notifyd_only_assigned_push_notifications,
    :fuzzy_label_picker,
    :reactions_position,
    :convert_to_tasklist_block,
    :otel_rack_middleware,
    :notifications_async_issues_subscription_button,
    :notifications_async_watch_repo_button,
    :allow_internal_org_config_repo_if_public_repos_disabled, # Global health repo for EMU orgs
    :global_health_files_repository_loader_new_fetch_implementation, # Global health repo for EMU orgs
    :owner_scoped_github_apps,
    :ghost_pilot_pr_autocomplete,
    :display_comment_actions,
    :may_post_comment_actions,
    :remove_shelf_limited_paths,
    :run_authzd_cap_filter_experiment_web,
    :use_billing_locked_rather_than_disabled,
    :optimize_participant_list_for_large_orgs,
    :timeline_no_count_optimization,
    :timeline_best_effort_count_optimization,
    :copilot_sku_isolation_discovery,
    :copilot_swe_agent_disallow,
  ].freeze

  REDIS_JOB_HASHING_FEATURES = [
    :job_hash_lock_write_safe_key,
    :job_hash_lock_skip_unsafe_key_write,
    :job_hash_lock_skip_unsafe_key_check,
  ]

  preload_features REDIS_JOB_HASHING_FEATURES

  DEFAULT_FEATURES = [
    :authnd_experiment,
    :copilot_conversational_ux_license_check,
    :gitrpc_always_include_request_id,
    :stacks_toggle,
    :emit_redis_command_size_metric,
    :two_factor_checkup,
    :issues_service_mutative_actions_rate_limits,
    :tasklist_block_morpheus,
    :api_insights_rest,
    :add_oauth_app_to_dog_tags,
    :track_mobile_query_name,
    :spokesd_request_timeout_header_spokes_api,
    :business_team_in_permit_and_access_level_for,
    :issues_react_disabled,
    :enterprise_teams_org_assignment,
    :run_authzd_cap_experiment,
    :run_authzd_cap_filter_experiment,
    :skip_model_importing_check_on_old_repositories,
  ]

  SHOW_WITH_REACT_FEATURES = SHOW_FEATURES + REACT_SERVER_SHOW_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHubUI::FeatureFlags.js_flags
  INDEX_WITH_REACT_FEATURES = REACT_SERVER_INDEX_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHubUI::FeatureFlags.js_flags
  CREATE_WITH_REACT_FEATURES = REACT_SERVER_CREATE_FEATURE_LIST + REACT_CLIENT_FEATURE_LIST + GitHubUI::FeatureFlags.js_flags

  preload_features SHOW_WITH_REACT_FEATURES, only: [:show]
  preload_features INDEX_WITH_REACT_FEATURES + [
    :slash_commands,
    :owner_scoped_github_apps,
    :remove_shelf_limited_paths,
  ], only: :index
  preload_features CREATE_WITH_REACT_FEATURES + [
    :remove_shelf_limited_paths,
    :copilot_sku_isolation_discovery,
  ], only: [:choose, :new]
  preload_features DEFAULT_FEATURES

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
    max: :issues_dashboard_without_rate_limit_max,
    ttl: 1.minute,
    key: :issues_dashboard_rate_limit_key,
    if: :issues_dashboard_without_referer_limits_enabled?,
    at_limit: :issues_dashboard_rate_limit_at_limit

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if pulls_only? || (current_repository && current_issue && current_issue.pull_request?)
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  def index
    issue_react_index_handler
  end

  def choose # rubocop:todo GitHub/UseRestfulActions
    issue_react_choose_new_handler
  end

  def dashboard # rubocop:todo GitHub/UseRestfulActions
    context_region_title "Issues"
    issue_react_dashboard_handler
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

    if @issue.pull_request?
      redirect_to show_pull_request_path(current_repository.owner, current_repository, current_issue)
      return
    end

    repo_without_issues = track_execution_time("repo_has_issues") do
      !current_repository.has_issues?
    end
    render_404 and return if repo_without_issues
    return redirect_to issue_path(current_repository.owner, current_repository, current_issue), status: 301 if is_issue_show_legacy_path?

    issue_react_show_handler(current_issue: current_issue)
  end

  def new
    issue_react_choose_new_handler
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

  private

  def indifferent_params
    params.permit!.to_h.with_indifferent_access
  end

  # We are overriding RepositoryControllerMethods#current_repository in order to
  # introduce strict_loading to help identify any n+1s during the removal of GraphQL in Issues#show views
  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    if is_issue_show_path? && owner && params[:repository].present?
      includes = [
        :network_privilege,
      ]

      includes << :tabs if GitHub.custom_tabs_enabled?

      if !logged_in?
        # logged out users have the old site header which requires this association to be preloaded
        includes << :mirror
        includes << :open_graph_image
      end

      if logged_in?
        if current_repository_label_count && (100..1000).cover?(current_repository_label_count)
          includes << :labels
        end
      end

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

      if current_repository_label_count && (100..1000).cover?(current_repository_label_count)
        includes << :labels
      end

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

  def repo_issues_required
    if  !params[:pulls_only] && !current_repository.has_issues?
      render_404
    end
  end

  def index_flow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @index_flow ||= Issue::ControlFlow.new(
      params: params,
      pulls_only: pulls_only?,
      repo:   current_repository,
      components: parsed_issues_query,
      current_user: current_user,
      current_path: T.must(request).fullpath,
    )
  end

  def route_supports_advisory_workspaces?
    return true if current_issue&.pull_request?
    return false if action_name != "index"
    index_flow.pulls_only
  end

  def enabled_new_issues_required
    if !current_repository.has_issues? || current_repository.archived?
      render_404
    end
  end

  def content_authorization_required
    authorize_content(:issue, repo: current_repository)
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

  # Private: queries for tracking issues associated with the given issue, if the feature is enabled
  #
  # Returns an array of tracking issue hashes
  def tracking_issues
    return [] unless tracking_issues_enabled?
    return [] unless @issue

    @issue.normalized_tracking_issues( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      viewer: current_user,
      cap_filter: cap_filter,
    )
  end

  def tracking_issues_enabled?
    !GitHub.enterprise? || current_repository&.owner&.feature_flag_enabled?(:tasklist_block, default: false)
  end

  def current_repository_label_count
    return nil if !params[:repository].present?
    @current_repository_label_count ||= owner&.find_repo_by_name(
      params[:repository],
    )&.labels&.count
  end

  def external_identity_session_required
    if !current_user&.feature_flag_enabled?(:issues_react_enforce_sso, default: false) && !current_repository.owner.feature_flag_enabled?(:issues_react_enforce_sso, default: false)
      return
    end
    unless required_external_identity_session_present?(target: current_repository.owner)
      render_external_identity_session_required(target: current_repository.owner)
    end
  end
end
