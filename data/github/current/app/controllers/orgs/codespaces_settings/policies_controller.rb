# typed: true
# frozen_string_literal: true

class Orgs::CodespacesSettings::PoliciesController < Orgs::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_codespaces_feature_enabled, except: [:index]

  javascript_bundle :settings
  javascript_bundle :codespaces

  include ::Codespaces::OrganizationsDependency
  include ::Orgs::RepositoryItemsHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:additional_repo_dialog_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:repo_dialog_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:additional_repo_dialog_list, :repo_dialog_list], optional: true

  def index
    direct_policy_groups = current_organization.policy_groups.visible.includes(:policy_constraints, :policy_group_memberships)

    inherited_policy_groups = if current_organization.business&.feature_flag_enabled?(:codespaces_enterprise_policies, default: false) && current_organization.business&.in_codespaces_salus_beta?
      Codespaces::PolicyGroup.parent_business_policies(current_organization)
    else
      []
    end

    render "settings/organization/codespaces/policies/index", locals: {
      org_ownership_enabled: current_organization.codespaces_ownership_set_to_organization?,
      policy_groups: direct_policy_groups + inherited_policy_groups,
    }
  end

  def new
    render "settings/organization/codespaces/policies/new"
  end

  def edit
    existing_policy = {
      name: current_policy_group.name,
      id: current_policy_group.id,
      targets_all_repositories?: targets_all_repositories?,
      targeted_repository_ids: targeted_repository_ids,
      current_policy_constraints: current_policy_group.serialized_policy_constraints
    }
    render "settings/organization/codespaces/policies/edit", locals: { existing_policy: existing_policy }
  end

  def add_constraint_dropdown # rubocop:todo GitHub/UseRestfulActions
    render Organizations::Settings::CodespacesPolicyForm::AddConstraintComponent.new(
      owner: current_organization,
      current_policy_constraint_names: JSON.parse(params[:current_policy_constraints]),
      all_repos_target: JSON.parse(params[:all_repos_target]),
      all_repos_host_setup_policy_exists: JSON.parse(params[:all_repos_host_setup_policy_exists]),
      all_repos_network_configuration_policy_exists:  JSON.parse(params[:all_repos_network_configuration_policy_exists]),
    ), layout: false
  end

  def repo_dialog_list # rubocop:todo GitHub/UseRestfulActions
    render partial: "settings/organization/codespaces/policies/repo_dialog_list", locals: {
      organization: current_organization,
      repositories: [],
      selected_repositories: targeted_repository_ids,
      repository_items_data_url: repository_items_data_url,
      repository_items_aria_id_prefix: "codespaces-policy-group-repository-target_id",
    }
  end

  def additional_repo_dialog_list # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render(Organizations::Settings::RepositoryItemsComponent.new(
          organization: current_organization,
          repositories: additional_repositories(Set.new),
          selected_repositories: targeted_repository_ids,
          current_page: page,
          total_count: current_organization_repos.count,
          data_url: repository_items_data_url(page: page + 1),
          aria_id_prefix: "codespaces-policy-group-repository-target-id",
          repository_identifier_key: :id,
        ), layout: false)
      end
    end
  end

  def create
    set_empty_value_constraints

    Codespaces::CreatePolicyGroup.call(
      name: policy_group_params[:name],
      owner: current_organization,
      target_type: :repositories,
      universal_membership: all_repositories_param,
      target_ids: policy_group_params[:repository_ids] || [],
      constraints: policy_group_params[:constraints],
      actor: current_user
    )

    flash[:notice] = "Policy '#{policy_group_params[:name]}' added"
    if request.xhr?
      render json: { success: true }
    else
      redirect_to action: "index"
    end
  rescue ActiveRecord::RecordInvalid => e
    render(json: { error: e.record&.errors&.full_messages&.to_sentence }, status: :unprocessable_entity)
  rescue ActionController::ParameterMissing => e
    render(json: { error: "Invalid payload" }, status: :unprocessable_entity)
  end

  def update
    context = {}
    previously_all_repositories = current_policy_group.universal_under_owner?
    set_empty_value_constraints

    Codespaces::PolicyGroup.transaction do
      current_policy_group.update!(name: policy_group_params[:name])

      repository_ids = []
      if all_repositories_param
        current_policy_group.apply_universal_membership!
      else
        repository_ids = current_policy_group.apply_entity_allowlist_membership!(policy_group_params[:repository_ids], :repositories)
      end

      constraints = current_policy_group.apply_constraints!(policy_group_params[:constraints])

      context.merge!(instrumentation_context(current_policy_group, constraints, repository_ids: repository_ids))
    end
    GitHub.instrument("codespaces.policy_group_updated", context)

    GitHub.dogstats.increment("codespaces.policy_group.updated", tags: ["membership:#{membership_update_tag(previously_all_repositories)}"])

    flash[:notice] = "Policy '#{policy_group_params[:name]}' updated"
    if request.xhr?
      render json: { success: true }
    else
      redirect_to action: "index"
    end
  rescue ActiveRecord::RecordInvalid => e
    render(json: { error: e.record&.errors&.full_messages&.to_sentence }, status: :unprocessable_entity)
  rescue ActionController::ParameterMissing => e
    render(json: { error: "Invalid payload" }, status: :unprocessable_entity)
  end

  def destroy
    current_policy_group.destroy!
    GitHub.instrument("codespaces.policy_group_deleted", { actor: current_user, org: current_organization, policy_group_id: current_policy_group.id, policy_group_name: current_policy_group.name })
    GitHub.dogstats.increment("codespaces.policy_group.destroyed")

    flash[:notice] = "Policy '#{current_policy_group.name}' deleted"
    redirect_to action: "index"
  end

  private

  def instrumentation_context(policy_group, policy_constraints, repository_ids:)
    {
      actor: current_user,
      org: current_organization,
      policy_group_id: policy_group.id,
      policy_group_name: policy_group.name,
      all_repositories: all_repositories_param,
      repository_nwos: current_organization.repositories.where(id: repository_ids).map(&:nwo).sort, # rubocop:disable GitHub/DoNotAllowNameWithOwner nwo is expected in instrumentation
      repository_ids: repository_ids,
      policy_constraints: policy_constraints.map(&:audit_log_data),
    }
  end

  def check_codespaces_feature_enabled
    render_404 unless org_policy.allow_org_setting?
  end

  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  def current_organization_repos # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_organization_repos if defined? @current_organization_repos
    @current_organization_repos = current_organization.repositories
  end

  def repository_items_data_url(page: 1)
    settings_org_codespaces_policies_additional_repo_dialog_list_path(
      organization_id: current_organization,
      page: page,
      identifier: params[:identifier]
    )
  end

  def targets_all_repositories?
    return @target_all_repositories if defined? @target_all_repositories
    @targets_all_repositories = current_policy_group.universal_under_owner?
  end

  def targeted_repository_ids # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @targeted_repository_ids if defined? @targeted_repository_ids
    return @targeted_repository_ids = [] if params[:identifier].nil?

    @targeted_repository_ids = case targets_all_repositories?
    when true
      []
    when false
      current_policy_group
        .policy_group_memberships
        .where(target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY)
        .map(&:target_id)
    end
  end

  def current_policy_group # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @current_policy_group ||=
      current_organization
      .policy_groups
      .visible
      .includes(:policy_constraints, :policy_group_memberships)
      .find(params[:identifier])
  end

  def policy_group_params
    params.require(:policy_group).permit(:name, :all_repositories, repository_ids: [], constraints: [:name, :value, value: []])
  end

  def set_empty_value_constraints
    params.require(:policy_group).require(:constraints).map! { |constraint| constraint.reverse_merge(value: []) }
  end

  def all_repositories_param
    all_repositories = ActiveModel::Type::Boolean.new.cast(policy_group_params[:all_repositories] || false)
  end

  def membership_update_tag(previously_all_repositories)
    if all_repositories_param == previously_all_repositories
      "no_change"
    elsif all_repositories_param
      "all_repositories"
    else
      "selected_repositories"
    end
  end

  def org_policy # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @org_policy ||= Codespaces::OrgPolicy.new(user: current_user, org: current_organization)
  end
end
