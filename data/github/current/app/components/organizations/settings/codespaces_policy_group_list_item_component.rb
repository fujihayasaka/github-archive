# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyGroupListItemComponent < ApplicationComponent
  attr_reader :policy_group, :owner, :inherited
  alias :inherited? :inherited

  def initialize(owner:, policy_group: nil)
    @owner = owner
    @policy_group = policy_group
    @inherited = policy_group.owner != owner
  end

  def target_description
    return "all repositories" if inherited?

    target_type = owner.is_a?(Business) ? "organization" : "repository"
    if policy_group.universal_under_owner?
      "all #{target_type.pluralize}"
    else
      pluralize(policy_group.policy_group_memberships.size, target_type)
    end
  end

  def delete_path
    return if inherited?

    if owner.is_a?(Organization)
      settings_org_codespaces_delete_policy_path(owner, policy_group)
    elsif owner.is_a?(Business)
      settings_codespaces_delete_policy_group_enterprise_path(identifier: policy_group.id, slug: owner.slug)
    end
  end

  def edit_path
    return if inherited?

    if owner.is_a?(Organization)
      settings_org_codespaces_policies_edit_path(identifier: policy_group.id, organization_id: owner.display_login)
    elsif owner.is_a?(Business)
      settings_codespaces_edit_policy_group_enterprise_path(identifier: policy_group.id, slug: owner.slug)
    end
  end
end
