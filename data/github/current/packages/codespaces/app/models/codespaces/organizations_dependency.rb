# typed: true
# frozen_string_literal: true

module Codespaces::OrganizationsDependency

  extend ActiveSupport::Concern
  include OrganizationsHelper

  def users_with_access
    User.where(
      id: UserRole.includes(:role).where(
        roles: { name: Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
        target_type: "Organization",
        target_id: current_organization.id,
        actor_type: "User"
      ).pluck(:actor_id)
    )
  end

  def teams_with_access
    Team.where(
      id: UserRole.includes(:role).where(
        roles: { name: Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
        target_type: "Organization",
        target_id: current_organization.id,
        actor_type: "Team"
      ).pluck(:actor_id)
    )
  end
end
