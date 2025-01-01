# typed: true
# frozen_string_literal: true

class Stafftools::RepositoriesController < StafftoolsController
  include Secrets::Helper
  include Variables::Helper
  include Actions::LargerRunnersHelper
  include EnterpriseManagedUsersHelper

  # rubocop:enable GitHub/MapToService
  map_to_service :branch_protection_rule, only: [:change_allow_force_push] # rubocop:todo GitHub/MapToService

  before_action :ensure_repo_exists, except: [:index]
  before_action :enterprise_required, only: [:index]
  before_action :ensure_can_set_network_privilege, only: [:hide_from_google, :hide_from_discovery, :require_login, :collaborators_only, :content_warning]
  before_action :ensure_trade_screening_delete_allowed, only: [:destroy]
  skip_before_action :ensure_secrets_enabled
  skip_before_action :ensure_variable_enabled # note the singular variable, ensure_variables_enabled is a different function

  javascript_bundle :"stafftools-repositories"

  layout :new_nav_layout
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:security]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:admin]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:actions_billing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:actions_latest_runs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    only: [:collaboration]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:database]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:disk]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:actions_workflows]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:actions_secrets]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::ActionsEnvironments,
    only: [:actions_variables]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:actions_self_hosted_runners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:actions_workflow_run_usage]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:actions_workflow_run_artifacts]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:actions_workflow_execution]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Pages,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:overview]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:permissions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:notifications]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index, :security, :notifications, :admin, :disk, :overview, :permissions,
      :actions, :actions_billing, :actions_workflows, :actions_workflow_execution,
      :actions_workflow_run_usage, :actions_secrets, :actions_latest_runs, :actions_variables,
      :actions_workflow_run_artifacts, :actions_self_hosted_runners, :database],
    optional: true

  private def new_nav_layout
    case action_name
    when "index"
      "stafftools"
    when "security", "collaborators", "permissions", "deploy_keys"
      "layouts/stafftools/repository/security"
    when "issues", "notifications", "events", "alerts"
      "layouts/stafftools/repository/collaboration"
    when "disk", "releases"
      "layouts/stafftools/repository/storage"
    when "actions", "actions_billing", "actions_workflows", "actions_latest_runs", "actions_workflow_execution", "actions_workflow_run_usage", "actions_workflow_run_artifacts", "actions_self_hosted_runners", "actions_secrets", "actions_variables"
      "layouts/stafftools/repository/actions"
    else
      "layouts/stafftools/repository/overview"
    end
  end

  def index
    index_view = Stafftools::RepositoryViews::IndexView.new(filter: params[:filter], page: current_page)
    repos = index_view.repositories_query
    render "stafftools/repositories/index", locals: { view: index_view, repos: repos }
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/database"
  end

  def deploy_keys # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/deploy_keys"
  end

  def disk # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/disk"
  end

  def overview # rubocop:todo GitHub/UseRestfulActions
    view = Stafftools::RepositoryViews::ShowView.new repository: current_repository

    ActiveSupport::Notifications.instrument "statistics.memory", data: memory_data do
      render "stafftools/repositories/overview", locals: { view: view }
    end
  end

  def releases # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/releases"
  end

  def unpublish_unsearchable_releases # rubocop:todo GitHub/UseRestfulActions
    result = Releases::Public.unpublish_unsearchable_releases(
      repo_id: current_repository.id,
      dry_run: false,
      perform_validations: params[:perform_validations] == "true"
    )

    flash[:notice] = "Unpublish finished. Searchable: #{result[:searchable]}. Unsearchable: #{result[:unsearchable]}. Unpublished IDs: #{result[:unpublished_ids]}"
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = "Try `skip validation` mode. Unpublish failed for release ID=#{e.record.id}. #{e}"
  ensure
    redirect_to :back
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/search"
  end

  def security # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/security"
  end

  def languages # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repositories/languages"
  end

  def show
    headers["Cache-Control"] = "no-cache, no-store"

    @counts = {
      releases: current_repository.releases.size,
      collabs: current_repository.members.size,
      deploy_keys: current_repository.public_keys.size,
      discussions: current_repository.discussions.size,
      hooks: Hook.hooks_for_target(current_repository).size,
      network_repos: current_repository.network.repositories.size,
      children: current_repository.children.size,
      issues: current_repository.issues.size, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pull_requests: current_repository.pull_requests.size,
      projects: current_repository.projects.size,
      all_branches: current_repository.heads.size.to_i, # if heads.size is nil, it's 0
      protected_branches: current_repository.protected_branches.size,
      invites: current_repository.repository_invitations.size,
      repository_advisories: current_repository.repository_advisories.size,
      siblings: [current_repository.parent&.children&.size.to_i - 1, 0].max,
    }

    @error_states = {
      billing: (current_repository.disabled? if GitHub.billing_enabled?),
      disabled: current_repository.access.disabling_reason,
      disk: current_repository.on_disk_status,
      fileserver: current_repository.fileserver_status,
      deleted: !current_repository.active? && current_repository.deleted_at.present?,
    }

    if current_repository.page
      @last_pages_build = current_repository.page.builds.first
    end

    render "stafftools/repositories/show", layout: "stafftools/repository"
  end

  # View a repo's events (the dashboard feed items)
  def events # rubocop:todo GitHub/UseRestfulActions
    @page_param = params[:events_page]
    render "stafftools/repositories/events"
  end

  def actions # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    tier = TrustTiers::Tier.for_repository(current_repository, TrustTiers::Tier::STAFFTOOLS_CLIENT).tier

    relevant_actions = [
      "checks.*",
      "repo.*actions*",
      "repo.*self_hosted_runner*",
      "repo.set_fork_pr_workflows_policy",
      "repo.set_public_fork_pr_workflows_policy",
      "workflows.*"
    ].join(" OR ")
    query = "repo_id:#{current_repository.id} AND (#{relevant_actions})"

    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        webevents
        | where repo_id == #{current_repository.id}
        | where action startswith "checks." or action matches regex "repo.*actions*"
        or action matches regex "repo.*self_hosted_runner*" or action == "repo.set_fork_pr_workflows_policy" or action == "repo.set_public_fork_pr_workflows_policy" or action matches regex "workflows.*"
      KQL
    end

    audit_log_info = fetch_audit_log_teaser query

    render "stafftools/repositories/actions",
      locals: {
        current_repository: current_repository,
        repository_tier: tier,
        audit_log_info: audit_log_info,
        oidc_sub_claim_template: actions_oidc_sub_claim_template
      }
  end

  def actions_workflow_execution # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    workflow_run = Actions::WorkflowRun.find_by(
      check_suite_id: params[:check_suite_id],
      repository_id: current_repository.id
    )
    return render_404 unless workflow_run

    actor_login = workflow_run.actor.display_login
    # use same permission as audit logs, since this is customer data, see config/stafftools_permissions.yml's `- name: Stafftools::SearchController`
    has_permissions = stafftools_action_authorized?(controller: Stafftools::SearchController, action: :audit_log)
    if has_permissions && actor_login == "dependabot#{Bot::LOGIN_SUFFIX}"
      workflow_run_backend_id = workflow_run.latest_workflow_run_execution&.external_id || workflow_run.check_suite&.external_id
      unless workflow_run_backend_id.nil?
        result = ActionsResults::Twirp.log_client.get_completed_run_log_archive(
          workflow_run_backend_id: workflow_run_backend_id
        )
        if result.call_succeeded?
          download_log_url = result.value.log_url
        else
          flash[:error] = "Unable to fetch log from results service"
        end
      end
    end

    show_annotations = ActiveRecord::Type::Boolean.new.deserialize(params[:show_annotations])
    if show_annotations
      check_suite = T.must(workflow_run.check_suite)
      check_suite_annotations = check_suite.annotations.where("created_at >= ?", check_suite.started_at || check_suite.created_at)
      latest_check_run_ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)

      check_run_annotations = CheckAnnotation
        .annotate("cross-shard-query-exempted")
        .where("check_run_id in (?)", latest_check_run_ids)
        .includes(:check_run)
      annotations = check_suite_annotations.to_a + check_run_annotations.to_a
    end
    render "stafftools/repositories/actions/workflow_execution", locals: {
      current_repository: current_repository,
      workflow_run: workflow_run,
      show_annotations: show_annotations,
      annotations: annotations,
      download_log_url: download_log_url
    }
  end

  def actions_workflow_run_usage # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled? && GitHub.billing_enabled?

    workflow_run = Actions::WorkflowRun.find_by(repository: current_repository, id: params[:workflow_run_id])
    return render_404 unless workflow_run

    # check suite needed later in view to get associated check runs, 404 if none
    return render_404 unless workflow_run.check_suite

    render "stafftools/repositories/actions/workflow_run_usage", locals: {
      current_repository: current_repository,
      workflow_run: workflow_run
    }
  end

  def actions_workflow_run_artifacts # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    workflow_run = Actions::WorkflowRun.find_by(repository: current_repository, id: params[:workflow_run_id])
    return render_404 unless workflow_run

    # check suite needed later to fetch artifacts, 404 if none
    return render_404 unless check_suite = workflow_run.check_suite
    artifacts = check_suite.artifacts.order(:name).limit(Artifact::MAX_READ_LIMIT)

    render "stafftools/repositories/actions/workflow_run_artifacts", locals: {
      current_repository: current_repository,
      workflow_run: workflow_run,
      artifacts: artifacts
    }
  end

  def force_cancel_suite # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    check_suite = current_repository.check_suites.find(params[:check_suite_id])
    return render_404 unless check_suite

    if check_suite.cancelable?
      cancel_actor = GitHub.enterprise? ? User.ghost : User.staff_user
      result = check_suite.cancel(actor: cancel_actor, force: true)

      if result.call_succeeded?
        flash[:notice] = "Workflow run force canceled succesfully"
      else
        if check_suite.force_set_cancellation_eligible?
          check_suite.force_set_cancellation_state(actor: User.staff_user)
          flash[:notice] = "Unable to force cancel the workflow run in the backend. The run however is older than 1 day so all non-completed checks data has been marked as canceled in the UI."
        else
          flash[:error] = "Unable to force cancel the workflow run in the backend. Updating just the checks UI to a canceled state is restricted due to potential negative side-effects since the run is not old enough. Try again after #{check_suite.created_at + 1.day}"
        end
      end
    end

    redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: check_suite.id)
  end

  def heal_check_suite # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    check_suite = current_repository.check_suites.find(params[:check_suite_id])
    return render_404 unless check_suite

    if check_suite.healable_for_actions?
      check_suite.mark_as_complete!
      flash[:notice] = "Check suite healed"
    end

    redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: check_suite.id)
  end

  def force_cancel_check_run # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    check_suite = current_repository.check_suites.find(params[:check_suite_id])
    return render_404 unless check_suite

    check_run = check_suite.check_runs.find(params[:check_run_id])
    return render_404 unless check_run

    if check_run.force_cancel_eligible_from_stafftools?
      check_run.force_cancel_from_stafftools
      flash[:notice] = "Check run #{check_run.id} cancelled"
    else
      flash[:error] = "Check run #{check_run.id} not cancelled, must be incomplete for more than 6 hours"
    end

    redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: check_suite.id)
  end

  def actions_billing # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && GitHub.billing_enabled?

    actions_plan_owner = ActionsPlanOwner.new(current_repository.owner)
    plan_name = actions_plan_owner.plan_name.titleize
    max_concurrent_jobs = actions_plan_owner.max_concurrent_jobs_guess
    max_concurrent_macos_jobs = actions_plan_owner.max_concurrent_macos_jobs_guess

    metered_billing_url = if current_repository.owner.organization?
      "/stafftools/#{this_user}/actions_packages"
    else
      "/stafftools/#{this_user}/metered_billing/actions"
    end

    render "stafftools/repositories/actions/billing",
           locals: {
             plan_name: plan_name,
             max_concurrent_jobs: max_concurrent_jobs,
             max_concurrent_macos_jobs: max_concurrent_macos_jobs,
             metered_billing_url: metered_billing_url
           }
  end

  def actions_workflows # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    limit = 100

    # Convert the workflows to an array to reduce the number of sql queries in the common case.
    workflows = current_repository.workflows.limit(limit).to_a
    if workflows.count == limit
      workflow_count = current_repository.workflows.count
    else
      workflow_count = workflows.count
    end

    render "stafftools/repositories/actions/workflows",
      locals: {
        workflow_count: workflow_count,
        workflows: workflows,
        workflow_type: :regular,
        limit: limit
      }
  end

  def refresh_repository_workflows # rubocop:todo GitHub/UseRestfulActions
    render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    current_repository.refresh_workflows

    flash[:notice] = "Repository workflows have been refreshed"
    redirect_to gh_actions_workflows_stafftools_repository_path(current_repository)
  end

  def actions_latest_runs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    search_id = (params[:query] || "").strip
    unless search_id.empty?
      search_runs = Actions::WorkflowRun
        .where(id: search_id, repository_id: current_repository.id)
        .or(Actions::WorkflowRun.where(check_suite_id: search_id, repository_id: current_repository.id))
      search_runs = (search_runs + CheckRun.where(id: search_id).map { |check_run| check_run.check_suite&.workflow_run }).uniq
      if search_runs.none?
        flash[:error] = "No results found for the given id. Try searching workflow run deletion audit logs. For checks created using third party GitHub apps, search under third party checks."
      else
        workflow_run = search_runs.first
        return redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: workflow_run.check_suite_id)
      end
    end

    render "stafftools/repositories/actions/latest_runs",
      locals: { workflow_runs: current_repository.workflow_runs.limit(50) }
  end

  def actions_self_hosted_runners # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    owner_settings = Actions::RepoRunnersView.new(settings_owner: current_repository, current_user: current_user)

    render "stafftools/repositories/actions/self_hosted_runners",
      locals: { runners: repo_runners, runner_groups: repo_runner_groups, larger_runners: larger_runners,  owner_settings: owner_settings }
  end

  def actions_secrets # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    secrets = secrets_for_repository(current_repository, current_user, app: actions_integration, fetch_environments: true)
    render "stafftools/repositories/actions/secrets",
      locals: { current_repository: current_repository, secrets: secrets }
  end

  def actions_variables # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    variables = variables_for_repository(current_repository, current_user, app: actions_integration, fetch_environments: true)
    render "stafftools/repositories/actions/variables",
      locals: { current_repository: current_repository, variables: variables, can_use_org_variables: repo_can_use_org_variables? }
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def actions_integration # rubocop:todo GitHub/UseRestfulActions
    # Always store secrets and variables with the prod app, even in lab.
    @integration ||= GitHub.launch_github_app
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def actions_oidc_sub_claim_template  # rubocop:todo GitHub/UseRestfulActions
    return nil unless GitHub.actions_enabled?

    configuration = RepositoryActionsOIDCConfig.get_configurations(current_repository.id)

    return nil if !configuration.present? || configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED].present?

    if configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE].present?
      configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE]
    elsif current_repository.owner.organization?
      org_level_template = OrganizationOIDCSubClaimTemplate.get_template_for_org(current_repository.owner.id)
      org_level_template.nil? ? nil : org_level_template.template
    else
      nil
    end
  end

  # View the notifications a repo has generated
  # If no "user" param is present, user will be nil causing the view to display all notifications
  def notifications # rubocop:todo GitHub/UseRestfulActions
    notification_params = params.to_unsafe_h.with_indifferent_access

    user = User.find_by(id: notification_params[:user].to_i)
    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: current_repository, request: request, params: notification_params, user: user)
    render "stafftools/repositories/notifications", locals: { view: notifications_view }
  end

  def collaboration # rubocop:todo GitHub/UseRestfulActions
    # Collaboration is dead! Long live collaboration!
    if current_repository.organization
      redirect_to gh_permissions_stafftools_repository_path(current_repository)
    else
      redirect_to gh_stafftools_repository_collaborators_path(current_repository)
    end
  end

  def permissions # rubocop:todo GitHub/UseRestfulActions
    if (@org = current_repository.organization)
      @abilities = Hash.new { |h, k| h[k] = current_repository.async_most_capable_action_or_role_for(k).sync }

      collab_abilities = Ability.where(
        actor_type: "User",
        subject_id: current_repository.id,
        subject_type: "Repository",
        priority: Ability.priorities[:direct],
      )
      .where("action >= ?", Ability.actions[params[:ability].presence || "read"])
      .pluck(:actor_id)

      team_abilities = current_repository.actor_ids_for_team_on_repo(
        min_action: params[:ability].presence || "read"
      )

      user_ids = Team.members_of(team_abilities, immediate_only: false).pluck(:id)
      user_ids += collab_abilities
      user_ids += current_repository.organization.admin_ids

      @users =
        User.where(id: user_ids.uniq)
        .where("login LIKE ?", "%#{params[:username]}%")
        .order("login ASC")
        .paginate(page: params[:page])

      search_user = (params[:query] || "").strip
      unless search_user.empty?
        user = User.find_by(id: search_user)
        if user.nil?
          error_message = "Couldn't find user with that ID"
        else
          can_review_bypass_request, reason = SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(current_repository, user)
        end
      end

      render "stafftools/repositories/permissions",
        locals: { can_review_bypass_request: can_review_bypass_request, can_bypass_reason: reason, error_message: error_message }
    else
      redirect_to gh_stafftools_repository_collaborators_path(current_repository)
    end
  end

  # Make this repo go away forever
  def destroy
    unless current_repository.name_with_display_owner.casecmp?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to gh_admin_stafftools_repository_path(current_repository)
    end

    current_repository.remove(current_user, staff: true)
    flash[:notice] = "Repository deleted"
    redirect_to stafftools_path
  end

  # Billing-lock this repo
  def lock # rubocop:todo GitHub/UseRestfulActions
    current_repository.lock_for_billing
    flash[:notice] = "Repository locked"
    redirect_to :back
  end

  # Migration-lock this repo
  def lock_for_migration # rubocop:todo GitHub/UseRestfulActions
    current_repository.lock_for_migration
    flash[:notice] = "Repository locked for migration"
    redirect_to :back
  end

  # Billing-unlock this repo
  def unlock # rubocop:todo GitHub/UseRestfulActions
    current_repository.unlock_including_descendants!
    flash[:notice] = "Repository unlocked"
    redirect_to :back
  end

  # Queue up a fsck job for this repo
  def fsck # rubocop:todo GitHub/UseRestfulActions
    current_repository.async_fsck
    flash[:notice] = "fsck job enqueued"
    redirect_to :back
  end

  def wiki_restore # rubocop:todo GitHub/UseRestfulActions
    current_repository.storage_adapter.restore_wiki
    flash[:notice] = "wiki restored from backup!"
    redirect_to :back
  end

  def pause_repo_invite_limit # rubocop:todo GitHub/UseRestfulActions
    RepositoryInvitationRateLimitOverride.override!(current_repository.id)
    flash[:notice] = "Repository invitation limit overridden for the next 24 hours."
    redirect_to :back
  end

  # Reindex the repo's metadata for search
  def reindex_repository # rubocop:todo GitHub/UseRestfulActions
    current_repository.reindex_repository
    flash[:notice] = "Reindexing #{current_repository.name_with_owner} ..."
    redirect_to :back
  end

  def purge_repository # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_repository
    flash[:notice] = "Purging #{current_repository.name_with_owner} from the search index ..."
    redirect_to :back
  end

  # Reindex the repo's code for search (Elastomer)
  def reindex_code # rubocop:todo GitHub/UseRestfulActions
    current_repository.reindex_code

    flash[:notice] = "Deleted existing documents and enqueued a code reindexing job"
    redirect_to :back
  end

  # Index code (with blackbird)
  def reindex_blackbird # rubocop:todo GitHub/UseRestfulActions
    BlackbirdOnboardReposJob.perform_later(current_user.id, [current_repository.id])

    flash[:notice] = "Repository queued for indexing with blackbird"
    redirect_to :back
  end

  # Index embeddings (with blackbird)
  def reindex_blackbird_embeddings # rubocop:todo GitHub/UseRestfulActions
    CopilotIndexedRepositories.find_or_create_by!(repository_id: current_repository.id).tap { |cir| cir.touch(:last_requested_at) }
    BlackbirdOnboardReposJob.perform_later(current_user.id, [current_repository.id])

    flash[:notice] = "Repository queued for semantic indexing with blackbird"
    redirect_to :back
  end

  # Route only available when using Elastomer-based code search.
  def purge_code # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_code
    flash[:notice] = "Purging source code from the search index..."
    redirect_to :back
  end

  # Route only available in GHES since we do not use Elastomer-based code
  # search outside of GHES
  def enable_code_search # rubocop:todo GitHub/UseRestfulActions
    current_repository.code_search_enabled = true
    current_repository.save!
    Search.add_to_search_index("code", current_repository.id)

    flash[:notice] = "Code search has been enabled and is now being indexed."
    redirect_to :back
  end

  def hide_from_google # rubocop:todo GitHub/UseRestfulActions
    current_repository.set_network_privilege(:noindex, params[:no_index] == "1", actor: current_user)
    flash[:notice] = "Repository #{current_repository} network privileges updated."
    redirect_to :back
  end

  def hide_from_discovery # rubocop:todo GitHub/UseRestfulActions
    current_repository.set_network_privilege(:hide_from_discovery, params[:hide_from_discovery] == "1", actor: current_user)
    Stafftools::NetworkPrivilege.recalculate_trending_repos
    flash[:notice] = "Repository #{current_repository} network privileges updated."
    redirect_to :back
  end

  def require_login # rubocop:todo GitHub/UseRestfulActions
    current_repository.set_network_privilege(:require_login, params[:require_login] == "1", actor: current_user)
    flash[:notice] = "Repository #{current_repository} network privileges updated."
    redirect_to :back
  end

  def content_warning # rubocop:todo GitHub/UseRestfulActions
    category = params[:category]
    category = nil if category.blank?

    sub_category = params[:sub_category]
    sub_category = nil if sub_category.blank?

    custom_sub_category = params[:custom_sub_category]
    custom_sub_category = nil if custom_sub_category.blank?

    instructions = params[:instructions]
    instructions = nil if instructions.blank?

    forks = params[:apply_to_forks] == "yes"

    begin
      options = {
        actor: current_user,
        forks: forks,
        notify_fork_owners: true,
        instructions: instructions,
      }
      if category.present?
        type = current_repository.apply_content_warning_later(category, sub_category, custom_sub_category, **options)
        flash[:notice] = "Applying #{type} content warning to #{current_repository.nwo}#{" and its forks" if forks}"
      else
        current_repository.remove_content_warning_later(**options)
        flash[:notice] = "Removing content warning for #{current_repository.nwo}#{" and its forks" if forks}"
      end

      redirect_back_with_anchor("#network-privileges") and return
    rescue TrustSafety::ContentWarnings::ValidationError => error
      flash[:error] = "Error applying content warning: #{error}"
    end

    redirect_to :back
  end

  def collaborators_only # rubocop:todo GitHub/UseRestfulActions
    current_repository.set_network_privilege(:collaborators_only, params[:collaborators_only] == "1", actor: current_user)
    flash[:notice] = "Repository #{current_repository} network privileges updated."
    redirect_to :back
  end

  # Reindex the repo's commits for search
  def reindex_commits # rubocop:todo GitHub/UseRestfulActions
    current_repository.reindex_commits
    flash[:notice] = "Deleted existing documents and enqueued a commits reindexing job"
    redirect_to :back
  end

  def purge_commits # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_commits
    flash[:notice] = "Purging commits from the search index ..."
    redirect_to :back
  end

  def fix_issue_transfers # rubocop:todo GitHub/UseRestfulActions
    RetryTransferIssueJob.perform_later(current_repository.id, current_user)
    flash[:notice] = "Transferring stuck issues..."
    redirect_to :back
  end

  # Reindex the repo's issues for search
  def reindex_issues # rubocop:todo GitHub/UseRestfulActions
    purge = params[:purge] == "true" ? true : false
    current_repository.reindex_issues(purge)
    reindex_count = current_repository.issues.where(pull_request_id: nil).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    flash[:notice] = "Reindexing #{reindex_count} issues ..."
    redirect_to :back
  end

  def purge_issues # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_issues
    flash[:notice] = "Purging issues from the search index ..."
    redirect_to :back
  end

  # Reindex the repo's projects for search
  def reindex_projects # rubocop:todo GitHub/UseRestfulActions
    purge = params[:purge] == "true" ? true : false
    current_repository.reindex_projects(purge)
    flash[:notice] = "Reindexing #{current_repository.projects.count} projects ..."
    redirect_to :back
  end

  def purge_projects # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_projects
    flash[:notice] = "Purging projects from the search index ..."
    redirect_to :back
  end

  def purge_releases # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_releases
    flash[:notice] = "Purging releases from the search index ..."
    redirect_to :back
  end

  # Reindex the repo's wiki for search
  def reindex_wiki # rubocop:todo GitHub/UseRestfulActions
    current_repository.reindex_wiki
    flash[:notice] = "Deleted existing documents and enqueued a wiki reindexing job"
    redirect_to :back
  end

  # Purge the repo's wiki from search
  def purge_wiki # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_wiki
    flash[:notice] = "Purging #{current_repository.name_with_owner} wiki from the search index ..."
    redirect_to :back
  end

  def reindex_discussions # rubocop:todo GitHub/UseRestfulActions
    purge = params[:purge] == "true" ? true : false
    current_repository.reindex_discussions(purge)
    flash[:notice] = "Reindexing #{current_repository.discussions.size} discussions ..."
    redirect_to :back
  end

  def purge_discussions # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_discussions
    flash[:notice] = "Purging discussions from the search index ..."
    redirect_to :back
  end

  def reindex_releases # rubocop:todo GitHub/UseRestfulActions
    current_repository.reindex_releases
    flash[:notice] = "Reindexing #{current_repository.releases.size} releases..."
    redirect_to :back
  end

  # Enqueue a job to rescan the repo's files and analyze the languages
  def analyze_language # rubocop:todo GitHub/UseRestfulActions
    current_repository.enqueue_analyze_language_breakdown
    flash[:notice] = "Language analysis job enqueued"
    redirect_to :back

  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  # Purge events related to this repo
  def purge_events # rubocop:todo GitHub/UseRestfulActions
    if current_user.feature_enabled?(:conduit_delete_resource_events)
      GitHub.conduit_client.delete_resource_events(
        resource_type: "repository",
        resource_id: current_repository.id
      )
    else
      Stratocasters.domain.drop_repo_events(current_repository)
    end

    flash[:notice] = "Removed all events"
    redirect_to :back
  end

  # Rebuild CommitContribution data for this repository. Sometimes needed to
  # reindex commits due to failed job or other indexing issue.
  def rebuild_commit_contributions # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("repo", tags: ["action:rebuild_commit_contributions", "type:repo"])

    CommitContribution.backfill(current_repository, reset = true)
    flash[:notice] = "Rebuild commit contributions job enqueued ..."
    redirect_to :back
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    if current_repository.set_archived
      flash[:notice] = "Repository successfully archived."
    else
      flash[:error] = "Failed to archive repository."
    end

    redirect_to :back
  end

  def block_archive_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.block_archive_resource(actor: this_user)
    redirect_to :back
  end

  def unblock_archive_download # rubocop:todo GitHub/UseRestfulActions
    current_repository.unblock_archive_resource(actor: this_user)
    redirect_to :back
  end

  def unarchive # rubocop:todo GitHub/UseRestfulActions
    if current_repository.unset_archived
      flash[:notice] = "Repository successfully unarchived."
    else
      flash[:error] = "Failed to unarchive repository."
    end

    redirect_to :back
  end

  # Based on https://github.com/github/github/blob/353eb3806fa45602ee389aea3cca1c35cd6595ab/app/controllers/jobs_controller.rb
  def disable_job_info # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"

    repo_disabled = current_repository.access.disabled?
    job = Stafftools::DisableRepositoryAccessStatus.new(current_repository).job_status

    # There are three possible statuses for the disable job: pending, success, and failure.
    # In order for the disable job status to accurately represent the expected UI state, the
    # repository must be in the prerequisite enabled/disabled state. If these two states don't
    # match, then the user has done something else since clicking "Disable Access" (e.g. they
    # reenabled the repo before the disable job expired).
    status =
      if (job&.success? || job&.started?) && repo_disabled
        200
      elsif job&.error? && !repo_disabled
        200
      elsif job&.pending? && !repo_disabled
        202
      else
        404
      end

    render status: status, json: { job: job.as_json }
  end

  # Disable a repository at the discretion of an enterprise admin.
  def admin_disable # rubocop:todo GitHub/UseRestfulActions
    # we no longer want to render_404 unless GitHub.enterprise? since this is now a unified path
    reason = GitHub.enterprise? ? "admin" : params[:reason]

    if !GitRepositoryAccess::REASONS.include?(reason)
      flash[:error] = "Failed to disable access to repository: Invalid reason '#{reason}'"
      redirect_to :back and return
    end

    if !GitHub.enterprise? && params[:tos_reason].blank?
      flash[:error] = "Must include ToS violating reason"
      redirect_to :back and return
    end

    if !GitHub.enterprise? && params[:content_formats].blank?
      flash[:error] = "Must specify at least one violating content format when disabling a repository"
      redirect_to :back and return
    end

    instructions = params[:instructions]
    email_template = params[:"email_template_#{reason}"]

    if email_template != nil && email_template.blank?
      flash[:error] = "Failed to disable access to repository: Must include notification for owner"
      redirect_to :back and return
    end

    if !GitHub.enterprise? && params[:details].blank?
      flash[:error] = "Must include audit log details when disabling a repository"
      redirect_to :back and return
    end

    begin
      Mustache.render(email_template) if email_template.present?
    rescue Mustache::Parser::SyntaxError
      flash[:error] = "Failed to disable access to repository: Invalid mustache template syntax"
      redirect_to :back and return
    end

    enqueued = current_repository.disable_access(reason, current_user,
      instructions: instructions,
      email_template: email_template,
      notify_fork_owners: true,
      disabling_detail: params[:details],
      tos_reason: params[:tos_reason],
      content_formats: params[:content_formats],
      source: params[:source],
      dsa_required: !GitHub.enterprise? && !params[:do_not_notify_dsa],
    )
    if enqueued
      flash[:notice] = "Repository has been enqueued to be disabled and the user will be contacted."

      # The line below is deprecated per https://github.com/github/trust-safety/issues/270#issuecomment-1050133117.
      # Keeping in place at least until the UAT is shipped per https://github.slack.com/archives/CP9BR2PS5/p1647611599712969?thread_ts=1647536490.658909&cid=CP9BR2PS5.
      StaffNote.create(user: current_user, notable: this_user, note: params[:staff_note] || params[:details])

      redirect_back_with_anchor("#danger-zone") and return
    else
      flash[:error] = "Failed to disable access to repository"
    end

    redirect_to :back
  end

  # Re-enable a repository that has been disabled for a size or tos violation.
  def remove_disable # rubocop:todo GitHub/UseRestfulActions
    TrustSafety::JobStatus.create(id: EnableRepositoryAccessJob.job_id(current_repository))

    if EnableRepositoryAccessJob.perform_later(current_repository, current_user)
      flash[:notice] = "Repository has been enqueued to be restored."
      redirect_back_with_anchor("#danger-zone") and return
    else
      flash[:error] = "Failed to restore access to repository."
    end

    redirect_to :back
  end

  def change_allow_force_push # rubocop:todo GitHub/UseRestfulActions
    val = params[:value].presence || false

    if val == "_clear"
      current_repository.clear_force_push_rejection(current_user)
    else
      current_repository.set_force_push_rejection val, current_user
    end

    flash[:notice] = case val
    when false
      "Force pushing is now allowed."
    when "all"
      "Force pushing is now blocked."
    when "default"
      "Force pushing is now blocked on the default branch."
    when "_clear"
      "Setting cleared. Force pushing will use the default setting."
    end

    redirect_to :back

  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  def change_ssh_access # rubocop:todo GitHub/UseRestfulActions
    val = params[:value].presence || "false"

    if val == "_clear"
      current_repository.clear_ssh(current_user)
    else
      val == "true" ? current_repository.enable_ssh(current_user) : current_repository.disable_ssh(current_user)
    end

    flash[:notice] = case val
    when "true"
      "Git SSH access now enabled."
    when "false"
      "Git SSH access now disabled."
    when "_clear"
      "Setting cleared. Instance default will be used."
    end

    redirect_to :back
  end

  def change_anonymous_git_access # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.anonymous_git_access_enabled?

    val = params[:value]&.to_s
    if current_repository.fork?
      flash[:error] = Repository::AnonymousGitAccess::FORK_ERROR
    elsif val == "true"
      current_repository.enable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now enabled."
    elsif val == "false"
      current_repository.disable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now disabled."
    else
      flash[:error] = "Failed to change anonymous Git read access."
    end

    redirect_to :back
  end

  def change_anonymous_git_access_locked # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.anonymous_git_access_enabled?

    val = params[:value]&.to_s
    if val == "true"
      current_repository.lock_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now locked."
    elsif val == "false"
      current_repository.unlock_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now unlocked."
    else
      flash[:error] = "Failed to change anonymous Git read access locked state."
    end

    redirect_to :back
  end

  # Toggles the "allow git graph" option on this repo
  def toggle_allow_git_graph # rubocop:todo GitHub/UseRestfulActions
    flash[:notice] = if !current_repository.toggle_allow_git_graph
      "Graphing is now enabled"
    else
      "Graphing is now disabled"
    end
    redirect_to :back

  rescue GitHub::DGit::UnroutedError
    flash[:error] = "Repository offline"
    redirect_to :back
  end

  # Toggles the 'public_push' option on this repo
  def toggle_public_push # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.public_push_enabled?

    if current_repository.public?
      current_repository.update public_push: !current_repository.public_push
      flash[:notice] = "Public push is #{current_repository.public_push? ? 'now' : 'no longer'} allowed"
    else
      flash[:error] = "Cannot toggle public push on private repo"
    end
    redirect_to :back
  end

  # Switch a fork to be public or private, matching its root repo.
  # Switch a public unforked repository to private.
  def toggle_permission # rubocop:todo GitHub/UseRestfulActions
    if !current_repository.fork? && in_network?
      flash[:error] = "Cannot change permissions on a root repo"
    elsif current_repository.public? == current_repository.root.public? && in_network?
      flash[:error] = "Cannot change a fork’s permissions to be different from its root"
    elsif current_repository.owner.emu_creating_public_repo?(current_repository.public? ? "private" : "public")
      flash[:error] = "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility"
    else
      new_perms = current_repository.public? ? "private" : "public"
      nwo = current_repository.name_with_owner

      current_repository.toggle_visibility(actor: current_user)

      flash[:notice] = "#{nwo} permissions changed to #{new_perms}"
    end
    redirect_to :back
  rescue Repositories::Error::VisibilityLocked => e
    flash[:error] = e.message
    redirect_to :back
  end

  def toggle_token_scanning # rubocop:todo GitHub/UseRestfulActions
    public_scanning = SecretScanning::Features::Repo::PublicScanning.new(current_repository)
    token_scanning = SecretScanning::Features::Repo::TokenScanning.new(current_repository)
    return render_404 unless token_scanning.stafftools_available? || public_scanning.stafftools_available?

    enable = params[:enable_token_scanning]
    on_network = params[:apply_enable_token_scanning_to_network]

    service_manager = SecurityProduct::ServiceManager.new(current_repository)
    if enable
      service_manager.toggle_services(this_user, services_to_enable: [[:token_scanning, { force?: true, use_staff_key: true, update_rest_of_network?: on_network, use_network_flag?: on_network }]])
    else
      service_manager.toggle_services(this_user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true, update_rest_of_network?: on_network, use_network_flag?: on_network }]])
    end

    flash[:notice] = "#{enable ? "Enabled" : "Disabled"} secret scanning on this repository#{on_network ? " and its network" : ""}."
    redirect_to :back
  end

  def toggle_generic_secret_scanning # rubocop:todo GitHub/UseRestfulActions
    enable = params[:enable_generic_secret_scanning]

    service_manager = SecurityProduct::ServiceManager.new(current_repository)
    if enable
      service_manager.toggle_services(this_user, services_to_enable: [[:token_scanning_generic_secrets, { force?: true, use_staff_key: true }]])
    else
      service_manager.toggle_services(this_user, services_to_disable: [[:token_scanning_generic_secrets, { force?: true, use_staff_key: true }]])
    end

    flash[:notice] = "#{enable ? "Enabled" : "Disabled"} generic secret scanning on this repository."
    redirect_to :back
  end

  def toggle_anonymous_release_download # rubocop:todo GitHub/UseRestfulActions
    enable = params[:enable_anonymous_release_download]
    current_repository.toggle_anonymous_release_download(enable, this_user)

    flash[:notice] = "#{enable ? "Enabled" : "Disabled"} anonymous release asset downloads on this repository."
    redirect_to :back
  end

  def in_network? # rubocop:todo GitHub/UseRestfulActions
    current_repository.root.all_forks_count > 0
  end

  def change_max_object_size # rubocop:todo GitHub/UseRestfulActions
    val = params[:value].presence

    if val
      if val == "_clear"
        current_repository.clear_max_object_size(current_user)
        flash[:notice] = "Setting cleared. Maximum object size will use the inherited default."
      else
        current_repository.set_max_object_size(val.to_i, @current_user)
        if val.to_i == 0
          flash[:notice] = "Maximum object size updated to unlimited"
        else
          flash[:notice] = "Maximum object size updated to #{val}MB"
        end
      end
    else
      flash[:error] = "Maximum object size value must be a positive integer or zero"
    end

    redirect_to :back
  end

  def change_warn_disk_quota # rubocop:todo GitHub/UseRestfulActions
    val = params[:value].presence
    change_disk_quota(:warn, val)
  end

  def change_lock_disk_quota # rubocop:todo GitHub/UseRestfulActions
    val = params[:value].presence
    change_disk_quota(:lock, val)
  end

  def change_disk_quota(kind, val) # rubocop:todo GitHub/UseRestfulActions
    if val
      v = val.to_i
      current_repository.set_disk_quota(kind: kind, value: v, user: @current_user)
      case v
      when 0
        flash[:notice] = "#{kind.to_s.capitalize} disk quota updated to unlimited"
      when current_repository.default_disk_quota(kind: kind)
        flash[:notice] = "#{kind.to_s.capitalize} disk quota set to default #{v}GB"
      else
        flash[:notice] = "#{kind.to_s.capitalize} disk quota updated to #{v}GB"
      end
    else
      flash[:error] = "#{kind.to_s.capitalize} disk quota value must be a positive integer or zero"
    end

    redirect_to :back
  end

  def admin # rubocop:todo GitHub/UseRestfulActions
    if GitHub.porter_available? && !params[:skip_porter]
      porter_status = Porter::StafftoolsClient.get_import_status(
        repository: current_repository,
        env:        request.env,
      )
    end

    issue_transfers = IssueTransfer.where(old_repository_id: current_repository.id, state: "errored")

    render "stafftools/repositories/admin", locals: {
      porter_status: porter_status,
      issue_transfers: issue_transfers,
      disable_templates: {
        size: Stafftools::Repository::DISABLE_TEMPLATE_FOR_SIZE_DOT_COM,
        tos: Stafftools::Repository::DISABLE_TEMPLATE_FOR_TOS,
        trademark: Stafftools::Repository::DISABLE_TEMPLATE_FOR_TRADEMARK,
        private_information: Stafftools::Repository::DISABLE_TEMPLATE_FOR_PRIVATE_INFORMATION,
      }
    }
  end

  def redetect_license # rubocop:todo GitHub/UseRestfulActions
    RepositorySetLicenseJob.perform_later(current_repository)
    flash[:notice] = "License detection job enqueued"
    redirect_to :back
  end

  def schedule_backup # rubocop:todo GitHub/UseRestfulActions
    RepositoryBackupNgJob.perform_later(current_repository.id, "repository")
    flash[:notice] = "Repository backup job scheduled"
    redirect_to :back
  end

  def schedule_wiki_backup # rubocop:todo GitHub/UseRestfulActions
    RepositoryBackupNgJob.perform_later(current_repository.id, "wiki")
    flash[:notice] = "Repository wiki backup job scheduled"
    redirect_to :back
  end

  def wiki_mark_as_broken # rubocop:todo GitHub/UseRestfulActions
    RepositoryWiki.find_by!(repository: current_repository).mark_as_broken
    flash[:warn] = "Wiki repository marked broken"
    redirect_to :back
  end

  def wiki_schedule_maintenance # rubocop:todo GitHub/UseRestfulActions
    RepositoryWiki.find_by!(repository: current_repository).schedule_maintenance
    flash[:notice] = "Maintenance job enqueued for wiki repository"
    redirect_to :back
  end

  def enabled_feature_flags # rubocop:todo GitHub/UseRestfulActions
    view = Stafftools::RepositoryViews::ShowView.new(repository: current_repository)
    render "stafftools/enabled_feature_flags/index", locals: { view: view, actor: view.repository }
  end

  private

  def memory_data
    {
      controller: {
        name: params[:controller],
        action: params[:action],
      },
      user: {
        login: current_user.login,
      },
      statistics: GC.stat,
    }
  end

  def larger_runners
    return [] unless current_repository.owner.organization? && current_repository.owner.can_use_larger_runners?
    larger_runners_list = Actions::LargerRunner.larger_runners_for(entity: current_repository, owner: current_repository.organization)
    @_larger_runners ||= larger_runners_list
  end

  def repo_runners # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_runners ||= Actions::Runner.for_entity(current_repository)
  end

  def repo_runner_groups
    return [] unless current_repository.owner.organization?
    @_runner_groups ||= Actions::RunnerGroup.for_entity(current_repository, include_runners: true)
  end

  def ensure_can_set_network_privilege
    unless current_repository.public?
      flash[:error] = "Network privileges can only be set on public repositories."
      redirect_to :back
    end
  end

  def ensure_trade_screening_delete_allowed
    return unless current_repository&.owner
    return unless current_repository.owner_trade_screening_delete_restricted?

    flash[:error] = "This action cannot be performed on an account that is trade restricted."
    redirect_to gh_admin_stafftools_repository_path(current_repository)
  end
end
