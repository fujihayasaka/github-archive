# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::PoliciesController < Orgs::Controller
  include Actions::PolicyHelper
  include Actions::RunnersHelper

  before_action :login_required

  before_action :ensure_user_has_runners_and_runner_groups_fine_grained_permission, only: [:update_repo_self_hosted_runners, :repo_self_hosted_runners_repos_dialog, :update_repo_self_hosted_runners_repos]
  before_action :ensure_user_has_actions_settings_fine_grained_permission, except: [:update_repo_self_hosted_runners, :repo_self_hosted_runners_repos_dialog, :update_repo_self_hosted_runners_repos, :index]
  before_action :ensure_user_has_access_to_any_actions_general_settings, only: [:index]
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_tenant_exists_when_ghes, only: [:index]
  before_action :dotcom_required, only: [:update_fork_pr_approvals_policy]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:repo_dialog, :repo_self_hosted_runners_repos_dialog]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:repo_dialog, :repo_self_hosted_runners_repos_dialog], optional: true

  def index
    log_access_metrics

    return render "settings/organization/actions/index", locals: {
      can_use_entity_selection: can_use_entity_selection?,
      can_use_org_runners: false
    } unless can_use_org_runners?

    render "settings/organization/actions/index", locals: {
      can_use_entity_selection: can_use_entity_selection?,
    }
  end

  def repo_dialog # rubocop:todo GitHub/UseRestfulActions
    render partial: "settings/organization/actions/repo_dialog", locals: {
      organization: current_organization,
      repositories: selected_repos,
      selected_repositories: selected_repos.map(&:global_relay_id),
      repository_items_data_url: repository_items_data_url,
      repository_items_aria_id_prefix: repository_items_aria_id_prefix,
    }
  end

  def update_repos # rubocop:todo GitHub/UseRestfulActions
    nodes_to_enable = (params[:enable] || []).to_set
    ids_to_enable = nodes_to_enable.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    nodes_to_disable = (params[:disable] || []).to_set
    ids_to_disable = nodes_to_disable.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }

    current_organization.repositories.where(id: ids_to_enable).each do |repo|
      repo.allow_actions(actor: current_user)
    end

    current_organization.repositories.where(id: ids_to_disable).each do |repo|
      repo.disallow_actions(actor: current_user)
    end

    redirect_to settings_org_actions_path
  end

  def update_actions_access # rubocop:todo GitHub/UseRestfulActions
    if Actions::PolicyUpdater::VALID_OPTIONS.include? params[:policy]
      Actions::PolicyUpdater.perform(entity: current_organization, policy: params[:policy], actor: current_user)
    else
      flash[:error] = "Sorry, there was an issue updating your settings."
    end

    redirect_to settings_org_actions_path
  end

  def update_allowed_actions # rubocop:todo GitHub/UseRestfulActions
    policy = params[:allowedactions].to_s

    if Actions::Policy::AllowedActionsForm::VALID_OPTIONS.include? policy
      if policy == Actions::Policy::AllowedActionsForm::SPECIFIED_ACTIONS
        # If both were not passed, just set one of them for now.
        params["firstparty"] = true unless %w(firstparty marketplace patterns).any? { |k| params.key? k }

        current_organization.enable_specified_actions_only(github_owned: params["firstparty"] || false, verified: params["marketplace"] || false, actor: current_user)

        if params[:patterns]
          patterns = params[:patterns].split(/,\s*/).map(&:strip)
          allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(current_organization, patterns: patterns, actor: current_user)
        end
      else
        Actions::AllowedTypesUpdater.perform(entity: current_organization, policy: policy, actor: current_user)
      end
    end

    if allowlist && allowlist.errors.any?
      flash[:error] = allowlist.errors.full_messages.to_sentence
    else
      flash[:notice] = "Actions policy updated."
    end

    redirect_to settings_org_actions_path
  end

  def update_repo_self_hosted_runners # rubocop:todo GitHub/UseRestfulActions
    if current_organization.repo_self_hosted_runners_disabled_by_owner?
      flash[:error] = "Your enterprise admin disabled this setting for your organization."
      redirect_to settings_org_actions_path
      return
    end

    case params[:policy]
    when Configurable::ActionsRepoSelfHostedRunners::NO_ENTITIES
      current_organization.disable_repo_self_hosted_runners(actor: current_user)
    when Configurable::ActionsRepoSelfHostedRunners::SELECTED_ENTITIES
      current_organization.enable_repo_self_hosted_runners_for_selected_entities(actor: current_user)
    when Configurable::ActionsRepoSelfHostedRunners::ALL_ENTITIES
      current_organization.enable_repo_self_hosted_runners(actor: current_user)
    else
      flash[:error] = "Sorry, there was an issue updating your settings."
      redirect_to settings_org_actions_path
      return
    end

    flash[:notice] = "Repo-level self-hosted runners settings changed."
    redirect_to settings_org_actions_path
  end

  def repo_self_hosted_runners_repos_dialog # rubocop:todo GitHub/UseRestfulActions
    repos = current_organization.repositories.where(id: current_organization.repo_self_hosted_runners_allowed_entities)
    policy = Orgs::ActionsSettings::RepositoryItemsController::REPO_SELF_HOSTED_RUNNERS
    items_url = settings_org_actions_repository_items_path(current_organization, {
      page: 1,
      policy: policy,
      policy_id: nil
    })

    render partial: "settings/organization/actions/repo_self_hosted_runners_repo_dialog", locals: {
      organization: current_organization,
      repositories: repos,
      selected_repositories: repos.map(&:global_relay_id),
      repository_items_data_url: items_url,
      repository_items_aria_id_prefix: policy,
    }
  end

  def update_repo_self_hosted_runners_repos # rubocop:todo GitHub/UseRestfulActions
    nodes_to_enable = (params[:enable] || []).to_set
    ids_to_enable = nodes_to_enable.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    nodes_to_disable = (params[:disable] || []).to_set
    ids_to_disable = nodes_to_disable.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }

    current_organization.repositories.where(id: ids_to_enable).each do |repo|
      repo.allow_repo_self_hosted_runners(actor: current_user)
    end

    current_organization.repositories.where(id: ids_to_disable).each do |repo|
      repo.disallow_repo_self_hosted_runners(actor: current_user)
    end

    redirect_to settings_org_actions_path
  end

  def update_retention # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_i || 0
      current_organization.set_actions_retention_limit(limit: limit, actor: current_user)
      flash[:notice] = "Retention setting saved."
    rescue Configurable::ActionsRetentionLimit::Error => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_org_actions_path
  end

  def update_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:fork_pr_workflows_policy] || {}
    set_fork_pr_workflows_policy(current_organization, form_policy)
  end

  def update_public_fork_pr_workflows_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:public_fork_pr_workflows_policy] || {}
    set_public_fork_pr_workflows_policy(current_organization, form_policy)
  end

  def update_fork_pr_approvals_policy # rubocop:todo GitHub/UseRestfulActions
    form_policy = params[:actions_fork_pr_approvals] || {}
    set_actions_fork_pr_approvals_policy(current_organization, form_policy)
  end

  def update_default_workflow_permissions # rubocop:todo GitHub/UseRestfulActions
    # Default workflow permission and PR approval allowed flags are stored together
    wf_default = params[:actions_default_workflow_permissions] || {}
    wf_pr_approve = params[:actions_workflow_permission_can_approve_pr] || {}
    set_default_and_approval_workflow_permissions(current_organization, wf_default, wf_pr_approve)
  end

  private

  # Metrics as part of https://github.com/github/actions-sudo/issues/475
  # Tracking how many users are accessing settings as non admins
  def log_access_metrics
    if current_organization.adminable_by?(current_user)
      GitHub.dogstats.increment("actions.org.settings.policies_controller", tags: ["admin:true"])
    else
      GitHub.dogstats.increment("actions.org.settings.policies_controller", tags: ["admin:false"])
    end
  end

  def ensure_tenant_exists_when_ghes
    ensure_tenant_exists if GitHub.enterprise?
  end

  def ensure_tenant_exists
    if current_organization.business
      result = Launch::Twirp.deployer_client.setup_tenant(current_organization.business)
      raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
    end

    result = Launch::Twirp.deployer_client.setup_tenant(current_organization)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def can_use_entity_selection?
    Billing::ActionsPermission.new(current_organization).status[:error][:reason] != "PLAN_INELIGIBLE" || GitHub.enterprise?
  end

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def selected_repos # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @_selected_repos if defined? @_selected_repos
    @_selected_repos = current_organization.repositories.where(id: current_organization.actions_allowed_entities)
  end

  def repository_items_data_url
    settings_org_actions_repository_items_path(current_organization, page: 1, policy: Orgs::ActionsSettings::RepositoryItemsController::ACCESS_POLICY, policy_id: nil)
  end

  def repository_items_aria_id_prefix
    Orgs::ActionsSettings::RepositoryItemsController::ACCESS_POLICY
  end

  def ensure_user_has_actions_settings_fine_grained_permission
    return render_404 if current_organization.nil?
    render_404 unless current_organization.can_write_organization_actions_settings?(current_user)
  end

  def ensure_user_has_runners_and_runner_groups_fine_grained_permission
    return render_404 if current_organization.nil?
    render_404 unless current_organization.can_write_organization_runners_and_runner_groups?(current_user)
  end

  def ensure_user_has_access_to_any_actions_general_settings
    return render_404 if current_organization.nil?
    render_404 unless current_organization.can_write_organization_actions_settings?(current_user) || current_organization.can_write_organization_runners_and_runner_groups?(current_user)
  end
end
