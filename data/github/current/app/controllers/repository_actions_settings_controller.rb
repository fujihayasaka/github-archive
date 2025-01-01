# typed: false
# frozen_string_literal: true

class RepositoryActionsSettingsController < AbstractRepositoryController
  include Actions::RunnersHelper
  include Actions::PolicyHelper
  include Actions::LargerRunnersHelper
  include GitHub::Tracing

  trace_method :runners
  trace_method :runner_groups

  before_action :login_required
  before_action :ensure_admin_access
  before_action :setup_actions_app, only: [:add_new_runner]
  before_action :setup_actions_app_on_policy_change, only: [:update_repository_share_policy]
  before_action :skip_unverified_and_spammy, only: [:delete_runner_modal, :delete_runner]
  before_action :sudo_filter, only: [:delete_runner_modal, :delete_runner]
  before_action :set_cache_control_no_store, only: [:delete_runner_modal]
  before_action :ensure_tenant_exists_when_ghes, only: [:index]
  before_action :ensure_repo_runners_enabled, only: [:add_new_runner]
  before_action :ensure_tenant_exists, only: [:add_new_runner]
  before_action :dotcom_required, only: [:update_fork_pr_approvals_policy]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:add_new_runner]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:runner_details]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:check_readiness]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:delete_runner_modal]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:list_runners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:runners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :add_new_runner, :runners, :runner_details]

  def index
    render "edit_repositories/pages/actions/general_settings"
  end

  def runners # rubocop:todo GitHub/UseRestfulActions
    shared_runners = []
    hosted_runner_group = nil
    runners = paginated_repo_runners
    runners.each do |runner|
      runner.is_in_default_group = true
    end

    runner_groups.each do |group|
      if group.hosted?
        hosted_runner_group ||= group
        if group.inherited?
          # always use the enterprise level hosted group if one is found
          hosted_runner_group = group
        end
      else
        group.runner_scale_sets.each do |scale_set|
          scale_set.inherited = group.inherited?
          shared_runners.append(scale_set)
        end

        group.runners.each do |runner|
          runner.inherited = group.inherited?
          runner.group_name = group.name
          runner.group = group
          shared_runners.append(runner)
        end
      end
    end

    if current_repository.owner.organization? && current_repository.owner.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: current_repository, owner: current_repository.organization)
      larger_runners.each do |larger_runner|
        shared_runners.append(larger_runner)
      end
    end

    shared_runners = shared_runners.sort_by { |runner| runner.view_priority }

    paginated_shared_runners = WillPaginate::Collection.create(shared_page, per_page, shared_runners.count) do |pager|
      pager.replace(shared_runners[((shared_page - 1) * per_page), per_page] || [])
    end

    render "edit_repositories/pages/actions/runner_settings", locals: {
      runners: runners,
      runner_scale_sets: repo_scale_sets,
      runner_groups: nil,
      hosted_runner_group: hosted_runner_group,
      shared_runners: paginated_shared_runners
    }
  end

  def runner_details # rubocop:todo GitHub/UseRestfulActions
    runner = Actions::Runner.get(current_repository, params[:id].to_i)

    return render_404 unless runner.present?

    if runner.check_run_global_id.present?
      check_run = CheckRun.includes(:check_suite, :repository).find(Platform::Helpers::NodeIdentification.from_global_id(runner.check_run_global_id)[1].to_i)
    end

    render "edit_repositories/pages/actions/runner_details", locals: {
      runner: runner,
      check_run: check_run,
      runner_group: nil,
      owner_settings: Actions::RepoRunnersView.new(settings_owner: current_repository, current_user: current_user)
    }
  end

  # Check for anything that needs to be configured before using Actions.
  # Currently just a check for self-hosted runners on GHES.
  def check_readiness # rubocop:todo GitHub/UseRestfulActions
    render json: {
      anyRunnersConfigured: any_runners_configured
    }
  rescue Actions::ServiceError
    # Return an error response so the client doesn't display a "no runners configured" warning.
    head(500)
  end

  def list_runners # rubocop:todo GitHub/UseRestfulActions
    redirect_to repository_actions_settings_runners_path
  end

  def add_new_runner # rubocop:todo GitHub/UseRestfulActions
    resp = Launch::Twirp.self_hosted_runners_client.list_downloads(current_repository)

    downloads = resp.value&.downloads

    if downloads.blank?
      # Actions aren't setup yet for this repo.
      return render "edit_repositories/pages/actions/add_runner_error"
    end

    scope = current_repository.runner_creation_token_scope
    expires_at = 1.hour.from_now
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)

    add_runner_data = runner_options(downloads: downloads, token: token)
    render "edit_repositories/pages/actions/add_runner", locals: {
      os: add_runner_data[:os],
      platform: add_runner_data[:platform],
      architecture: add_runner_data[:architecture],
      platform_options: add_runner_data[:platform_options],
      downloads: add_runner_data[:downloads],
      selected_download: add_runner_data[:selected_download],
      token: add_runner_data[:token]
    }
  end

  def delete_runner_modal # rubocop:todo GitHub/UseRestfulActions
    scope = current_repository.runner_registration_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: 1.hour.from_now)

    respond_to do |format|
      format.html do
        render partial: "edit_repositories/pages/actions/delete_runner_modal",
               locals: { token: token, runner_id: params[:id], runner_os: params[:os] }
      end
    end
  end

  def delete_runner # rubocop:todo GitHub/UseRestfulActions
    delete_status = delete_runner_for(current_repository, id: params[:id].to_i, actor: current_user)

    if delete_status == "deleted"
      flash[:notice] = "Runner successfully deleted."
    else
      flash[:error] = "Sorry, there was a problem deleting your runner."
    end

    redirect_to repository_actions_settings_runners_path
  end

  def update_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    if current_repository.public?
      render status: 401, json: { errors: "Attempt to update private fork pull request workflow policy from public repository." }
      return
    end

    form_policy = params[:fork_pr_workflows_policy] || {}

    set_fork_pr_workflows_policy(current_repository, form_policy)
  end

  def update_public_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    if current_repository.private?
      render status: 401, json: { errors: "Attempt to update public fork pull request workflow policy from private repository." }
      return
    end

    form_policy = params[:public_fork_pr_workflows_policy] || {}

    set_public_fork_pr_workflows_policy(current_repository, form_policy)
  end

  def update_fork_pr_approvals_policy # rubocop:todo GitHub/UseRestfulActions
    unless current_repository.public?
      flash[:error] = "You can only change the fork pull request outside collaborators policy for public repositories."
      return redirect_to :back
    end

    form_policy = params[:actions_fork_pr_approvals] || {}

    set_actions_fork_pr_approvals_policy(current_repository, form_policy)
  end

  def update_repository_share_policy # rubocop:todo GitHub/UseRestfulActions
    return redirect_to :back unless is_actions_repository_sharing_allowed?

    form_policy = params[:actions_repository_share_policy] || {}
    set_actions_repository_share_policy(current_repository, form_policy)
  end

  def update_default_workflow_permissions # rubocop:todo GitHub/UseRestfulActions
    # Default workflow permission and PR approval allowed flags are stored together
    wf_default = params[:actions_default_workflow_permissions] || {}
    wf_pr_approve = params[:actions_workflow_permission_can_approve_pr] || {}
    set_default_and_approval_workflow_permissions(current_repository, wf_default, wf_pr_approve)
  end

  def update_retention # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_i || 0
      current_repository.set_actions_retention_limit(limit: limit, actor: current_user)
      flash[:notice] = "Retention setting saved."
    rescue Configurable::ActionsRetentionLimit::Error => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to repository_actions_settings_path
  end

  def update_cache_size # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_f.to_i
      current_repository.set_actions_cache_size_limit(limit: limit, actor: current_user)
      flash[:notice] = "Cache size saved."
    rescue ActionsCacheUsagePolicy::InvalidLimitError => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to repository_actions_settings_path
  end

  private

  def setup_actions_app
    return if current_repository.actions_app_installed?

    # Actions has not been setup yet, install the app.
    GitHub.dogstats.increment("actions.self_hosted_tenant_setup", tags: ["runner_type:repo"])
    ActiveRecord::Base.connected_to(role: :writing) do
      current_repository.enable_actions_app(
        actor: current_user,
        entry_point: :repository_actions_settings_controller_setup_actions_app
      )
    end
  end

  def is_actions_repository_sharing_allowed?
    return false if current_repository.public?
    return true if current_repository.internal?
    true
  end

  def setup_actions_app_on_policy_change
    return if params[:actions_repository_share_policy] == Configurable::ActionsRepositorySharePolicy::NONE
    return unless is_actions_repository_sharing_allowed?
    return if current_repository.actions_app_installed?

    ActiveRecord::Base.connected_to(role: :writing) do
      result = current_repository.enable_actions_app(
        actor: current_user,
        entry_point: :repository_actions_settings_controller_setup_actions_app_on_policy_change
      )
      if !result.success?
        GitHub.logger.info(
          "Unable to setup actions app for the repository",
          "gh.repo.name_with_owner" => current_repository.nwo,
          "gh.repo.id" => current_repository.id,
          "gh.repo.enable_actions_app_result_reason" => result.reason
        )
      end
    end
  end

  def ensure_tenant_exists_when_ghes
    ensure_tenant_exists if GitHub.enterprise?
  end

  def ensure_repo_runners_enabled
    if current_repository.repo_self_hosted_runners_disabled?
      redirect_to repository_actions_settings_runners_path
    end
  end

  def ensure_tenant_exists
    result = Launch::Twirp.deployer_client.setup_tenant(current_repository)

    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def unverified_or_spammy
    current_user.spammy? || current_repository.owner.spammy? || current_user.should_verify_email?
  end

  def skip_unverified_and_spammy
    render_404 if unverified_or_spammy
  end

  def repo_runners(propagate_errors: false)
    @_runners ||= Actions::Runner.for_entity(current_repository, propagate_errors: propagate_errors)
  end

  def runner_groups(propagate_errors: false)
    return [] unless current_repository.owner.organization?
    return [] unless can_use_org_runners?(current_repository.owner)
    runner_groups = Actions::RunnerGroup.for_entity(
      current_repository,
      include_runners: true,
      include_hosted_runner_groups: false,
      include_runner_scale_sets: true,
    ).select { |runner_group| runner_group.runners.any? || runner_group.runner_scale_sets.any? }

    return runner_groups.select(&:default?) unless current_repository.owner_can_use_actions_enterprise_features? || current_repository.owner_can_use_actions_team_features?

    runner_groups
  end

  def any_runners_configured
    return true if repo_runners(propagate_errors: true).length > 0

    runner_groups(propagate_errors: true).each do |group|
      return true if group.runners.length > 0
    end

    false
  end

  def paginated_repo_runners
    resp = Launch::Twirp.self_hosted_runners_client.list_runners(
      current_repository,
      page: page,
      per_page: per_page,
      exclude_elastic_runners: true
    )

    runners = Actions::Runner.from_rpc_collection(Array(resp.value&.runners), owner: current_repository)
    total = resp.value&.total_runners

    WillPaginate::Collection.create(page, per_page, total.to_i) do |pager|
      pager.replace runners
    end
  end

  def repo_scale_sets
    scale_sets = Actions::RunnerScaleSet.for_entity(current_repository)
    scale_sets.map do |scale_set|
      scale_set.is_in_default_group = true
      scale_set
    end
  end

  def per_page
    per_page = params[:per_page].to_i
    per_page = per_page.zero? ? 100 : per_page

    per_page.clamp(1, 100)
  end

  def page
    page = params[:page].to_i

    [page, 1].max
  end

  def shared_page
    shared_page = params[:shared_page].to_i

    [shared_page, 1].max
  end
end
