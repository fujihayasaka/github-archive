# typed: true
# frozen_string_literal: true

class ClassroomOrganization < SimpleDelegator

  def self.locate(organization_id:)
    if organization = Organization.find_by(id: organization_id)
      new(organization)
    end
  end

  def adminable_by?(teacher)
    T.bind(self, T.untyped)
    super(teacher.user)
  end

  def classroom_codespaces_enabled?
    classroom_codespaces_setup_status[:codespaces_allowed] \
    && classroom_codespaces_setup_status[:codespaces_billing_free] \
    && classroom_codespaces_setup_status[:codespaces_limit] == Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS
  end

  def classroom_codespaces_setup_status
    {
      codespaces_allowed: organization.codespaces_feature_enabled?,
      codespaces_billing_free: FeatureFlag.vexi.enabled?("codespaces_billing_free", organization, default: false),
      codespaces_limit: organization.organization_codespaces_user_limit
    }
  end

  def enable_classroom_codespaces(teacher)
    organization.accept_organization_codespaces_terms(actor: teacher.user)
    organization.update_organization_codespaces_user_limit(
      Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
      actor: teacher.user
    )
    set_organization_codespaces_billing_free
    set_codespaces_policy(actor: teacher.user)
  end

  def set_organization_codespaces_billing_free
    FeatureFlag.vexi_management.add_feature_flag_actors("codespaces_billing_free", [organization]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
  end

  def set_codespaces_policy(actor:)
    return if organization.policy_groups.exists?(name: "Education Codespaces Benefit Policy")

    Codespaces::CreatePolicyGroup.call(
        name: "Education Codespaces Benefit Policy",
        owner: organization,
        target_type: :repositories,
        universal_membership: true,
        constraints: [{ name: "codespaces.allowed_machine_types", value: ["basicLinux32gb"] }],
        actor: actor
    )
  end

  def disable_classroom_codespaces(teacher)
    result = Codespaces::OrganizationOptOut.call(organization: organization, actor: teacher.user)
    return false unless result.success?

    Codespaces::OrgSettingsChangedJob
      .perform_later(
        context: organization.id,
        event_type: Codespaces::Events::ORG_CODESPACES_DISABLED,
        actor_id: teacher.user.id
      )
    remove_codespaces_policy(actor: teacher.user)
    remove_organization_codespaces_billing_free
  end

  def remove_codespaces_policy(actor:)
    if (policy_group = organization.policy_groups.find_by(name: "Education Codespaces Benefit Policy"))
      policy_group.destroy!
      GitHub.instrument("codespaces.policy_group_deleted", { actor: actor, org: organization, policy_group_id: policy_group.id, policy_group_name: policy_group.name })
      GitHub.dogstats.increment("codespaces.policy_group.destroyed")
    end
  end

  def remove_organization_codespaces_billing_free
    FeatureFlag.vexi_management.remove_feature_flag_actors("codespaces_billing_free", [organization]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    true # Result of the disable operation
  end

  def meets_minimal_plan_for_classroom_codespaces?
    %w[team enterprise].include?(plan)
  end

  def plan
    T.bind(self, T.untyped)
    super.display_name
  end

  private

  def organization
    __getobj__
  end
end
