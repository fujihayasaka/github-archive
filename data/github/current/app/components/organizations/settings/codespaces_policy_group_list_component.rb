# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyGroupListComponent < ApplicationComponent
  attr_reader :policy_groups, :owner, :disable_creation

  def initialize(owner:, policy_groups: [], disable_creation: false)
    @owner = owner
    @policy_groups = policy_groups
    @disable_creation = disable_creation
  end

  def new_policy_url
    if owner.is_a?(Organization)
      settings_org_codespaces_policies_new_path(owner)
    elsif owner.is_a?(Business)
      settings_codespaces_new_policy_group_enterprise_path(slug: owner.slug)
    end
  end
end
