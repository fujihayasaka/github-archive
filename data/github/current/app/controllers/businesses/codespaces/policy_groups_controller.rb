# typed: strict
# frozen_string_literal: true

class Businesses::Codespaces::PolicyGroupsController < Businesses::BusinessController
  extend T::Sig
  include GitHub::Memoizer

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required
  before_action :enterprise_policies_feature_flag_required
  before_action :host_setup_policy_feature_flag_required, only: [:host_setup_repository_select]

  javascript_bundle :businesses
  javascript_bundle :codespaces
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :new, :edit, :add_constraint_dropdown, :org_dialog_list, :host_setup_repository_select]

  sig { void }
  def index
    render "businesses/codespaces_settings/policy_groups_index", locals: {
      policy_groups: Codespaces::PolicyGroup.visible.where(owner: this_business),
    }
  end

  sig { void }
  def new
    render "businesses/codespaces_settings/new_policy_group"
  end

  sig { void }
  def create
    set_empty_value_constraints

    Codespaces::CreatePolicyGroup.call(
      name: policy_group_params[:name] || "",
      owner: this_business,
      target_type: :organizations,
      universal_membership: ActiveModel::Type::Boolean.new.cast(policy_group_params[:all_organizations] || false),
      target_ids: organization_ids_param,
      constraints: policy_group_params[:constraints],
      actor: current_user
    )

    flash[:notice] = "Policy '#{policy_group_params[:name]}' added"
    if request.xhr?
      render json: { success: true }
    else
      redirect_to settings_codespaces_policies_enterprise_path(slug: this_business.slug)
    end
  rescue ActiveRecord::RecordInvalid => e
    render(json: { error: e.record&.errors&.full_messages&.to_sentence }, status: :unprocessable_entity)
  rescue ActionController::ParameterMissing => e
    render(json: { error: "Invalid payload" }, status: :unprocessable_entity)
  end

  sig { void }
  def edit
    existing_policy = {
      name: current_policy_group.name,
      id: current_policy_group.id,
      targets_all_repositories?: targets_all_organizations?,
      targeted_repository_ids: targeted_organization_ids,
      current_policy_constraints: current_policy_group.serialized_policy_constraints
    }
    render "businesses/codespaces_settings/edit_policy_group", locals: { existing_policy: existing_policy }
  end

  sig { void }
  def update
    context = {}
    previously_all_orgs = current_policy_group.universal_under_owner?
    set_empty_value_constraints

    Codespaces::PolicyGroup.transaction do
      current_policy_group.update!(name: policy_group_params[:name])

      org_ids = []
      if all_organizations_param
        current_policy_group.apply_universal_membership!
      else
        org_ids = current_policy_group.apply_entity_allowlist_membership!(organization_ids_param, :organizations)
      end

      constraints = current_policy_group.apply_constraints!(policy_group_params[:constraints])

      context.merge!(instrumentation_context(current_policy_group, constraints, organization_ids_param))
    end
    GitHub.instrument("codespaces.policy_group_updated", context)

    GitHub.dogstats.increment("codespaces.policy_group.updated", tags: ["membership:#{membership_update_tag(previously_all_orgs)}"])

    flash[:notice] = "Policy '#{policy_group_params[:name]}' updated"
    if request.xhr?
      render json: { success: true }
    else
      redirect_to settings_codespaces_policies_enterprise_path(slug: this_business.slug)
    end
  rescue ActiveRecord::RecordInvalid => e
    render(json: { error: e.record&.errors&.full_messages&.to_sentence }, status: :unprocessable_entity)
  rescue ActionController::ParameterMissing => e
    render(json: { error: "Invalid payload" }, status: :unprocessable_entity)
  end

  sig { void }
  def destroy
    current_policy_group.destroy!
    GitHub.instrument("codespaces.policy_group_deleted", { actor: current_user, business: this_business, policy_group_id: current_policy_group.id, policy_group_name: current_policy_group.name })
    GitHub.dogstats.increment("codespaces.policy_group.destroyed")

    flash[:notice] = "Policy '#{current_policy_group.name}' deleted"
    redirect_to settings_codespaces_policies_enterprise_path(slug: this_business.slug)
  end

  sig { void }
  def add_constraint_dropdown # rubocop:todo GitHub/UseRestfulActions
    render Organizations::Settings::CodespacesPolicyForm::AddConstraintComponent.new(
      owner: this_business,
      current_policy_constraint_names: JSON.parse(params[:current_policy_constraints] || "[]"),
      all_repos_target: JSON.parse(params[:all_repos_target] || "false"),
      all_repos_host_setup_policy_exists: false,
      all_repos_network_configuration_policy_exists: false,
    ), layout: false
  end

  sig { void }
  def org_dialog_list # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/codespaces_settings/org_dialog_list", locals: {
      business: this_business,
      organizations: this_business.organizations,
      selected_organizations: targeted_organization_ids,
    }
  end

  sig { void }
  def host_setup_repository_select # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/codespaces_settings/host_setup_repository_select", locals: {
      view: create_view_model(
        Codespaces::RepositorySelectView,
        layout: false,
        phrase: params[:q],
        remote_ip: request.remote_ip,
        cap_filter: cap_filter,
        business: this_business,
      )
    }, formats: :html
  end

  private

  sig { void }
  def enterprise_policies_feature_flag_required
    render_404 unless this_business.feature_enabled?(:codespaces_enterprise_policies) && this_business.in_codespaces_salus_beta?
  end

  sig { void }
  def host_setup_policy_feature_flag_required
    render_404 unless this_business.feature_enabled?(:codespaces_host_setup_policy) && this_business.feature_enabled?(:codespaces_salus_beta_customers)
  end

  sig { returns(Codespaces::PolicyGroup) }
  memoize def current_policy_group
    this_business.policy_groups.visible.includes(:policy_constraints, :policy_group_memberships).find(params[:identifier])
  end

  sig { returns(T::Boolean) }
  memoize def targets_all_organizations?
    current_policy_group.universal_under_owner?
  end

  sig { returns(T::Array[Integer]) }
  memoize def targeted_organization_ids
    return [] if params[:identifier].nil?
    return [] if targets_all_organizations?

    org_ids = current_policy_group
      .policy_group_memberships
      .where(target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_USER)
      .map(&:target_id)

    Organization.where(id: org_ids).map(&:global_relay_id)
  end

  sig { returns(ActionController::Parameters) }
  def policy_group_params
    params.require(:policy_group).permit(:name, :all_organizations, organization_ids: [], constraints: [:name, :value, value: []])
  end

  sig { returns(T::Array[Integer]) }
  def organization_ids_param
    (policy_group_params[:organization_ids]&.filter_map(&:presence) || []).map do |global_relay_id|
      Platform::Helpers::NodeIdentification.from_global_id(global_relay_id)[1].to_i
    end
  end

  sig { returns(T.untyped) }
  def set_empty_value_constraints
    params.require(:policy_group).require(:constraints).map! { |constraint| constraint.reverse_merge(value: []) }
  end

  sig { returns(T::Boolean) }
  def all_organizations_param
    ActiveModel::Type::Boolean.new.cast(policy_group_params[:all_organizations] || false)
  end

  sig { params(previously_all_organizations: T::Boolean).returns(String) }
  def membership_update_tag(previously_all_organizations)
    if all_organizations_param == previously_all_organizations
      "no_change"
    elsif all_organizations_param
      "all_organizations"
    else
      "selected_organizations"
    end
  end

  sig { params(policy_group: Codespaces::PolicyGroup, policy_constraints: T::Array[Codespaces::PolicyConstraint], org_ids: T::Array[Integer]).returns(T::Hash[T.untyped, T.untyped]) }
  def instrumentation_context(policy_group, policy_constraints, org_ids)
    {
      actor: current_user,
      policy_group_id: policy_group.id,
      policy_group_name: policy_group.name,
      policy_constraints: policy_constraints.map(&:audit_log_data),
      business: this_business,
      all_organizations: all_organizations_param,
      org_logins: this_business.organizations.where(id: org_ids).map(&:display_login),
      org_ids:,
    }
  end
end
