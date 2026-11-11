# typed: true
# frozen_string_literal: true

require "react_payload"

class ActionsController < AbstractRepositoryController
  include ActionsControllerMethods
  include ActionsHelper
  include FeatureFlagHelper
  include TreeHelper

  layout "repository"

  around_action :track_and_report_render_view_time, only: [:index]
  around_action :track_and_report_graphql_executions, only: [:index]
  around_action :track_and_report_mysql_executions, only: [:index]
  around_action :record_stats, only: [:index]
  before_action :login_required, except: [:index]
  before_action :actions_enabled_for_repo?, except: [:index, :layout_data]
  before_action :installable_by_current_user?, only: [:enable]
  before_action :actions_already_installed?, only: [:enable]
  before_action :add_csp_exceptions, only: [:new]
  before_action :should_show_selected_workflow_run?, except: [:index, :layout_data]
  skip_before_action :cap_pagination, only: [:index]

  javascript_bundle :actions, only: :index
  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Authnd,
    only: [:index, :layout_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:new_with_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    only: [:workflow_run_item, :check_run_item]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :new_with_filter], optional: true

  def index
    unless GitHub.actions_enabled? || show_only_required_workflows?
      return render "actions/ghes_enable_actions_blankslate" if GitHub.actions_packages_enterprise_setup_pending?
      return render_404
    end

    return render_404 if current_repository.actions_disabled? && !show_only_required_workflows? && !selected_workflow&.can_view_run_list_when_actions_disabled?

    if show_enable_actions_blankslate?
      emit_stat("render_enable_actions", ["fork:#{current_repository.fork?}"])
      render "actions/enable_actions_blankslate"
    elsif has_workflow_runs_or_file?
      show_survey_prompt = Actions::Survey.show_survey_prompt_for_user(current_user)
      Actions::Survey.emit_stat("shown") if show_survey_prompt

      repo_blocked = current_repository.action_invocation_blocked?
      user_blocked = current_user&.action_invocation_blocked?

      default_branch_sha = current_repository.default_branch_ref&.target_oid
      begin
        show_link_to_workflow = if selected_workflow&.required?
          show_link_to_required_workflow?
        else
          default_branch_sha.present? && current_repository.tree_entry(default_branch_sha, selected_workflow&.path).present?
        end
      rescue GitRPC::NoSuchPath
        show_link_to_workflow = false
      end

      return render_404 if selected_workflow && should_hide_spammy_workflow?

      # If the user is trying to get past the page limit
      if current_page > max_allowed_page
        page_limit_reached = true

        # Recommend search with a created_at filter to get past limit
        last_page_runs = paged_workflow_runs(max_allowed_page)
        if last_page_runs.present?
          recommended_date_filter = "<#{last_page_runs.last.created_at.strftime("%F") }"
        end
      end

      workflow_runs = page_limit_reached ? Actions::WorkflowRun.none.paginate(page: 1) : paged_workflow_runs

      if use_react_ui?
        # The workflow_runs_list route forces format: :html, but the data router
        # sends Accept: application/json. Override the format so respond_with_react
        # picks the correct format block.
        request.format = :json if react_data_router_request?
        return render_actions_workflows_react(workflow_runs, repo_blocked: repo_blocked, user_blocked: user_blocked)
      end

      render "actions/index", locals: {
        workflow_run_filters: workflow_run_filters,
        workflow_runs: workflow_runs,
        workflows: workflows,
        required_workflows: required_workflows,
        workflow_pages_count: workflow_pages_count,
        required_workflow_pages_count: workflow_pages_count(fetch_required_workflows: true),
        selected_workflow_name: selected_workflow_name || workflow_name_query,
        selected_workflow: selected_workflow,
        show_survey_prompt: show_survey_prompt,
        page_title: index_page_title,
        repo_blocked: repo_blocked,
        user_blocked: user_blocked,
        show_link_to_workflow: show_link_to_workflow,
        page_limit_reached: page_limit_reached,
        recommended_date_filter: recommended_date_filter,
        show_only_required_workflows: show_only_required_workflows?,
        show_runners_view: show_runners_view?,
        show_attestations_view: show_attestations_view?,
        show_actions_usage_metrics: show_actions_usage_metrics?,
        allow_pinning: allow_pinning?,
        show_actions_not_enabled_banner: show_actions_not_enabled_banner?,
      }
    elsif !logged_in? || !current_user_can_push?
      render "actions/actions_blankslate"
    else
      redirect_to actions_onboarding_path
    end
  end

  def enable # rubocop:todo GitHub/UseRestfulActions
    result = current_repository.enable_actions_app(actor: current_user, entry_point: :actions_controller_enable)

    if result.success?
      emit_stat("enable", ["result:success", "fork:#{current_repository.fork?}"])
      redirect_to actions_path, flash: { notice: "Actions Enabled." }
    else
      reason = result.reason || ""
      emit_stat("enable", ["result:failed", "fork:#{current_repository.fork?}", "reason:#{reason}"])
      redirect_to actions_path, flash: { notice: "Unable to enable Actions for this repository." }
    end
  end

  def layout_data # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless show_react_ui_toggle?

    page = [params[:page].to_i, 1].max

    respond_to do |format|
      format.html do
        render_404
      end

      format.json do
        render_react_json(payload: workflows_layout_payload(page: page))
      end
    end
  end

  def new
    if current_repository.writable_by?(current_user) && !show_only_required_workflows?
      filter_options = Actions::FilterOptions.new(include_preview_templates: include_preview_templates?)
      view = create_view_model(
        Actions::StarterWorkflowsView,
        repository: current_repository,
        language_category_filter: language_category_filter,
        filter_options: filter_options,
        selected_category: selected_category
      )

      render "actions/new", locals: {
        workflows: workflows,
        view: view
      }
    else
      render "actions/deny_read_only_users"
    end
  end

  def new_with_filter # rubocop:todo GitHub/UseRestfulActions
    return render "actions/deny_read_only_users" unless current_repository.writable_by?(current_user)

    filter_options = Actions::FilterOptions.new(
      search_query: search_query,
      category_slug: category_slug,
      include_preview_templates: include_preview_templates?
    )
    view = create_view_model(
      Actions::StarterWorkflowsView,
      repository: current_repository,
      filter_options: filter_options,
      selected_category: selected_category
    )

    render "actions/all_workflow_templates", locals: {
      workflows: workflows,
      view: view
    }
  end

  def workflow_runs # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request&.xhr?

    workflow_runs = paged_workflow_runs
    render partial: "actions/workflow_runs", locals: { workflow_runs: workflow_runs, selected_workflow: selected_workflow }
  end

  def workflow_run_item # rubocop:todo GitHub/UseRestfulActions
    check_suite = current_repository.check_suites.find_by(id: params[:workflow_run_id])
    return head :not_found unless check_suite
    workflow_run = check_suite.workflow_run
    return head :not_found unless workflow_run && request&.xhr?

    render Actions::WorkflowRunItemComponent.new(
      workflow_run_item: workflow_run,
      user_has_push_access: current_user_can_push?,
      current_repository: current_repository,
      user_is_site_admin: current_user && current_user&.site_admin?,
    ), layout: false
  end

  def check_run_item # rubocop:todo GitHub/UseRestfulActions
    check_run = Checks.domain.check_runs.for_id(params[:check_run_id].to_i, repository_id: current_repository.id) if params[:check_run_id]
    return head :not_found unless check_run && request&.xhr?

    render Actions::Runners::CheckRunItemComponent.new(
      check_run: check_run,
      os_icon: (params[:os_icon] || "").to_sym
    ), layout: false
  end

  private

  def global_nav_selected_link
    :repo_actions
  end

  def use_elasticsearch?
    workflow_run_filters.present? || current_user&.spammy?
  end

  def max_allowed_page
    if use_elasticsearch?
      ::Search::Query::max_offset_default / DEFAULT_PER_PAGE
    else
      GitHub.max_ui_pagination_page
    end
  end

  def paged_workflow_runs(page = current_page)
    if params[:workflow_file_name] && !selected_workflow
      # file name was passed in but we did not find a workflow
      Actions::WorkflowRun.none.paginate(page: 1)
    elsif use_elasticsearch?
      if FeatureFlag.vexi.enabled?(:actions_elastic_search_incident, default: false)
        flash[:error] = "We are having problems searching workflow runs. The results may not be complete."
      end

      filtered_workflow_runs(page)[:workflow_runs]
    else
      paged_workflow_runs_from_db(page)
    end
  end

  def paged_workflow_runs_from_db(page)
    paginated_scope =
      if selected_workflow
        current_repository
          .workflow_runs
          .from("#{Actions::WorkflowRun.table_name} USE INDEX FOR JOIN (index_workflow_runs_on_workflow_id_repository_id_user_hidden)")
          .where(workflow_id: selected_workflow.id)
      else
        current_repository
          .workflow_runs
          .from("#{Actions::WorkflowRun.table_name} USE INDEX FOR JOIN (index_workflow_runs_on_repository_id_user_hidden_imposer_repo_id)")
      end

    # Filter out spammy runs unless current user is a site admin
    if !current_user&.site_admin?
      paginated_scope = paginated_scope.where(user_hidden: false)
    end

    paginate_options = {
      page: page,
      per_page: DEFAULT_PER_PAGE,
    }

    # Cap total_entries via a bounded COUNT to avoid full index scans on large repos.
    # Uses raw SQL to prevent ActiveRecord from adding model scopes to the outer query.
    # Generates: SELECT COUNT(*) FROM (SELECT 1 FROM workflow_runs USE INDEX ... WHERE ... LIMIT 2501) AS bounded
    if FeatureFlag.vexi.enabled?(:actions_cap_workflow_runs_pagination, current_repository, default: false)
      max_total = max_allowed_page * DEFAULT_PER_PAGE
      inner_sql = paginated_scope.reselect("1").unscope(:order).limit(max_total + 1).to_sql
      bounded_count = Actions::WorkflowRun.connection.select_value(
        "SELECT COUNT(*) FROM (#{inner_sql}) AS bounded"
      ).to_i
      paginate_options[:total_entries] = [bounded_count, max_total].min
    end

    paginated_scope = paginated_scope
      .includes(:repository, :workflow)
      .most_recent
      .paginate(paginate_options)

    workflow_runs =
      if selected_workflow
        # Use a straightforward query for now. We have a great index for a single workflow, and the corresponding
        # experiment in the workflow runs api hasn't yielded dividends as of March 2023. See https://github.com/github/c2c-actions-experience/issues/6780
        paginated_scope
      else
        # Workaround not having a great index for sorting by the primary key by selecting the ids in a nested select.
        scope = current_repository.workflow_runs.where("`workflow_runs`.`id` IN (SELECT * FROM (?) subquery_for_limit)", paginated_scope.reselect(:id)).order(paginated_scope.order_values)
        scope = scope.includes(:repository, :workflow)
        scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
        scope = scope.per_page(paginated_scope.per_page)
        scope.current_page = paginated_scope.current_page
        scope.total_entries = paginated_scope.total_entries

        scope
      end

    GitHub::PrefillAssociations.prefill_batch_method(workflow_runs, :trigger)
    GitHub::PrefillAssociations.prefill_associations(workflow_runs, { check_suite: [:creator, :head_repository] })
    workflow_runs
  end

  def show_enable_actions_blankslate?
    return false unless current_repository.writable_by?(current_user)

    return false unless actions_app_not_installed?

    # If there are workflow runs, we shouldn't hide them behind the enable blankslate
    # even if the Actions App is not installed.
    # This will likely occur when a dynamic workflow is run, which doesn't require
    # an Actions App installation.
    # If there are workflow files a user wants to trigger, they will need to push a workflow file
    # manually to trigger the automatic app installation.
    return false if has_workflow_runs?

    has_workflow_file?
  end

  def show_actions_not_enabled_banner?
    # When dynamic workflows run before Actions is enabled, users have no way to enable it.
    # Show a banner with an enable button.
    return false unless current_repository.writable_by?(current_user)
    return false unless actions_app_not_installed?
    return false unless has_workflow_runs?
    return false unless has_workflow_file?

    true
  end

  def actions_app_not_installed? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @_actions_app_not_installed if defined?(@_actions_app_not_installed)

    @_actions_app_not_installed = GitHub.launch_github_app.installations_on(
      current_repository.owner,
    ).with_repository(current_repository).none?
  end

  def filtered_workflow_runs(page = current_page)
    return @_filtered_workflow_runs if defined?(@_filtered_workflow_runs)

    should_hide_spammy = !current_user&.site_admin?
    @_filtered_workflow_runs = Actions::WorkflowRun.search(
      query: workflow_query,
      workflow_id: selected_workflow&.id,
      workflow: params[:workflow],
      repo: current_repository,
      current_user: current_user,
      remote_ip: request&.remote_ip,
      user_session: user_session,
      page: page,
      per_page: DEFAULT_PER_PAGE,
      hide_spammy_runs: should_hide_spammy,
    )
  end

  def language_category_filter
    params[:language_category]
  end

  def category_slug
    params[:category]
  end

  def include_preview_templates?
    params[:preview] == "true"
  end

  def search_query
    params[:query]
  end

  def all_workflow_runs # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_all_workflow_runs ||= current_repository.workflow_runs
  end

  def has_workflow_runs?
    all_workflow_runs.any?
  end

  memoize def has_workflow_file?
    current_repository.workflow_file_present?(current_branch_or_tag_name)
  end

  def has_workflow_runs_or_file?
    has_workflow_runs? || has_workflow_file?
  end

  def installable_by_current_user?
    render_404 unless current_repository.writable_by?(current_user)
    render_404 unless has_workflow_runs_or_file?
  end

  def actions_already_installed?
    unless actions_app_not_installed?
      redirect_to actions_path, flash: { notice: "Actions Enabled." }
    end
  end

  def should_hide_spammy_workflow?
    return false if current_user&.site_admin?
    return false unless selected_workflow&.spammy?
    return false if current_user&.spammy? && selected_workflow&.workflow_runs.all? { |wf_run| wf_run.actor_id == current_user&.id }
    true
  end

  def emit_stat(suffix, tags = [])
    GitHub.dogstats.increment("actions_controller.#{suffix}", tags: tags)
  end

  def index_page_title
    return selected_workflow_name if selected_workflow_name
    return "Not found" if params[:workflow_file_name] && selected_workflow.nil?

    workflow_names = Array(workflow_run_filters[:workflow])
    if workflow_names.length == 1
      workflow_names.first
    elsif workflow_names.length > 1
      "Selected workflows"
    else
      "All workflows"
    end
  end

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end

  memoize def stats
    ::PageStats.new(
      controller_name: "actions",
      action_name: action_name,
      viewer: current_user,
      pjax: pjax?,
    )
  end

  def record_stats
    stats.entity = current_repository

    stats.instrument_controller_action do
      yield
      response.successful?
    end
  end

  def use_react_ui?
    show_react_ui_toggle? && (params[:react] == "true" || react_data_router_request?)
  end

  def react_data_router_request?
    request.env["HTTP_GITHUB_IS_REACT"] == "true"
  end

  def show_react_ui_toggle?
    FeatureFlag.vexi.enabled?(:actions_workflows_react_toggle, current_user, default: false)
  end
  helper_method :show_react_ui_toggle?

  def toggle_ui_url(react)
    url_for(request.query_parameters.except(:host, :port, :protocol).merge(react: react, only_path: true))
  end
  helper_method :toggle_ui_url

  def render_actions_workflows_react(workflow_runs, repo_blocked:, user_blocked:)
    react_toggle = toggle_ui_url("false")

    if params[:workflow_file_name]
      respond_with_react(
        app_name: "actions-workflows",
        title: selected_workflow_name || "Workflow Runs",
        payload: WorkflowRunsRoutePayload.new(
          workflow_runs: workflow_runs.to_a,
          react_toggle: react_toggle,
          repository: current_repository,
          pinned_workflow_ids: memoized_pinned_workflow_ids,
          repo_blocked: repo_blocked,
          user_blocked: user_blocked,
          show_only_required_workflows: show_only_required_workflows?,
          show_actions_not_enabled_banner: show_actions_not_enabled_banner?
        ),
        nested_payloads: -> { [workflows_layout_payload] }
      )
    else
      respond_with_react(
        app_name: "actions-workflows",
        title: "All Workflow Runs",
        payload: AllWorkflowRunsRoutePayload.new(
          workflow_runs: workflow_runs.to_a,
          react_toggle: react_toggle,
          repository: current_repository,
          pinned_workflow_ids: memoized_pinned_workflow_ids,
          repo_blocked: repo_blocked,
          user_blocked: user_blocked,
          show_only_required_workflows: show_only_required_workflows?,
          show_actions_not_enabled_banner: show_actions_not_enabled_banner?
        ),
        nested_payloads: -> { [workflows_layout_payload] }
      )
    end
  end

  memoize def memoized_pinned_workflow_ids
    Actions::PinnedWorkflow.where(repository_id: current_repository.id).pluck(:workflow_id)
  end

  def workflows_layout_payload(page: 1)
    all_workflows = unbound_workflows_for_pinning
    total_count = all_workflows.count

    if page == 1
      offset = 0
      limit = WORKFLOWS_FIRST_PAGE
    else
      offset = WORKFLOWS_FIRST_PAGE + (page - 2) * WORKFLOWS_PER_PAGE
      limit = WORKFLOWS_PER_PAGE
    end

    page_workflows = all_workflows.offset(offset).limit(limit)
    WorkflowsLayoutRoutePayload.new(
      workflows: page_workflows.map { |w| { id: w.id, name: w.name, path: w.path, state: w.state } },
      total_count: total_count,
      pinned_workflow_ids: memoized_pinned_workflow_ids,
      allow_pinning: allow_pinning?,
      show_deployments: current_repository.deployments.any?,
      show_attestations: show_attestations_view?,
      show_runners: show_runners_view?,
      show_usage_metrics: show_actions_usage_metrics?,
    )
  end

  class WorkflowRunsRoutePayloadBase < ReactPayload::Base
    abstract!

    sig do
      params(
        workflow_runs: T::Array[Actions::WorkflowRun],
        react_toggle: String,
        repository: Repository,
        pinned_workflow_ids: T::Array[Integer],
        repo_blocked: T::Boolean,
        user_blocked: T::Boolean,
        show_only_required_workflows: T::Boolean,
        show_actions_not_enabled_banner: T::Boolean
      ).void
    end
    def initialize(workflow_runs:, react_toggle:, repository:, pinned_workflow_ids:, repo_blocked:, user_blocked:, show_only_required_workflows:, show_actions_not_enabled_banner:)
      @workflow_runs = workflow_runs
      @react_toggle = react_toggle
      @alive_channel = ::GitHub::WebSocket::Channels.signed_workflow_runs(repository)
      @pinned_workflow_ids = pinned_workflow_ids
      @repo_blocked = repo_blocked
      @user_blocked = user_blocked
      @show_only_required_workflows = show_only_required_workflows
      @show_actions_not_enabled_banner = show_actions_not_enabled_banner
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      {
        workflowRuns: serialize_workflow_runs(@workflow_runs),
        reactToggle: @react_toggle,
        aliveChannel: @alive_channel,
        pinnedWorkflowIds: @pinned_workflow_ids,
        repoBlocked: @repo_blocked,
        userBlocked: @user_blocked,
        showOnlyRequiredWorkflows: @show_only_required_workflows,
        showActionsNotEnabledBanner: @show_actions_not_enabled_banner,
      }
    end

    private

    sig { params(runs: T::Array[Actions::WorkflowRun]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_workflow_runs(runs)
      runs.map do |run|
        {
          name: run.name,
          runNumber: run.run_number,
          id: run.id,
          workflowFilePath: run.workflow_file_path,
        }
      end
    end
  end

  class AllWorkflowRunsRoutePayload < WorkflowRunsRoutePayloadBase
    sig { override.returns(String) }
    def route_id
      "allWorkflowRunsRoute"
    end
  end

  class WorkflowRunsRoutePayload < WorkflowRunsRoutePayloadBase
    sig { override.returns(String) }
    def route_id
      "workflowRunsRoute"
    end
  end

  class WorkflowsLayoutRoutePayload < ReactPayload::Base
    sig do
      params(
        workflows: T::Array[T::Hash[Symbol, T.untyped]],
        total_count: Integer,
        pinned_workflow_ids: T::Array[Integer],
        allow_pinning: T::Boolean,
        show_deployments: T::Boolean,
        show_attestations: T::Boolean,
        show_runners: T::Boolean,
        show_usage_metrics: T::Boolean,
      ).void
    end
    def initialize(workflows:, total_count:, pinned_workflow_ids:, allow_pinning:, show_deployments:, show_attestations:, show_runners:, show_usage_metrics:)
      @workflows = workflows
      @total_count = total_count
      @pinned_workflow_ids = pinned_workflow_ids
      @allow_pinning = allow_pinning
      @show_deployments = show_deployments
      @show_attestations = show_attestations
      @show_runners = show_runners
      @show_usage_metrics = show_usage_metrics
    end

    sig { override.returns(String) }
    def route_id
      "workflowsLayoutRoute"
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      {
        workflows: @workflows,
        totalCount: @total_count,
        pinnedWorkflowIds: @pinned_workflow_ids,
        allowPinning: @allow_pinning,
        showDeployments: @show_deployments,
        showAttestations: @show_attestations,
        showRunners: @show_runners,
        showUsageMetrics: @show_usage_metrics,
      }
    end
  end
end
