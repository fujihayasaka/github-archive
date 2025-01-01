# typed: true
# frozen_string_literal: true

class ActionsController < AbstractRepositoryController
  include ActionsControllerMethods
  include ActionsHelper
  include FeatureFlagHelper
  include ReactHelper
  include TreeHelper

  layout "repository"

  around_action :track_and_report_render_view_time, only: [:index]
  around_action :track_and_report_graphql_executions, only: [:index]
  around_action :track_and_report_mysql_executions, only: [:index]
  around_action :record_stats, only: [:index]
  before_action :login_required, except: [:index]
  before_action :actions_enabled_for_repo?, except: [:index]
  before_action :installable_by_current_user?, only: [:enable]
  before_action :actions_already_installed?, only: [:enable]
  before_action :add_csp_exceptions, only: [:new]
  before_action :should_show_selected_workflow_run?, except: [:index]
  skip_before_action :cap_pagination, only: [:index]

  javascript_bundle :actions, only: :index
  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  preload_features [:actions_workflow_list_pinning], only: [:index]

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
    only: [:index]

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

    return render_404 if current_repository.actions_disabled? && !show_only_required_workflows?
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
        allow_pinning: allow_pinning?,
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
      flamingo_action = ActionsPrompt::FlamingoActions.new(current_repository)
      analytics_event(
        category: "Flamingo PR Actions Prompt",
        action: "action.enable_actions",
        label: "ref_repo_id:#{current_repository.id}"
      ) if flamingo_action.allowed_experience?
      emit_stat("enable", ["result:success", "fork:#{current_repository.fork?}"])
      redirect_to actions_path, flash: { notice: "Actions Enabled." }
    else
      reason = result.reason || ""
      emit_stat("enable", ["result:failed", "fork:#{current_repository.fork?}", "reason:#{reason}"])
      redirect_to actions_path, flash: { notice: "Unable to enable Actions for this repository." }
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
      render "actions/new", locals: { workflows: workflows, view: view }
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
    check_run = CheckRun.includes(:workflow_job_run, check_suite: [:workflow_run], repository: [:owner]).find_by(id: params[:check_run_id], repository_id: current_repository.id)
    return head :not_found unless check_run && request&.xhr?

    render Actions::Runners::CheckRunItemComponent.new(
      check_run: check_run,
      os_icon: (params[:os_icon] || "").to_sym
    ), layout: false
  end

  private

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
      if GitHub.flipper[:actions_elastic_search_incident].enabled?
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

    paginated_scope = paginated_scope
      .includes(:repository, :workflow)
      .most_recent
      .paginate(
        page: page,
        per_page: DEFAULT_PER_PAGE,
      )

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
    return workflow_name_query if workflow_name_query
    return "Not found" if params[:workflow_file_name] && selected_workflow.nil?
    "All workflows"
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
    stats.add_tags "actions_workflow_list_enabled:#{repository_feature_enabled?(:actions_workflow_list_pinning)}"
    stats.entity = current_repository

    stats.instrument_controller_action do
      yield
      response.successful?
    end
  end
end
