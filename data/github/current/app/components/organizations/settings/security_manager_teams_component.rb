# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityManagerTeamsComponent < ApplicationComponent

  ANCHOR = "security-manager-teams-list"
  LEARN_MORE_LINK = "#{GitHub.help_url}/organizations/managing-peoples-access-to-your-organization-with-roles/managing-security-managers-in-your-organization".freeze

  def initialize(actor:, organization:)
    @actor = actor
    @organization = organization

    @can_add_security_managers = authorizer.can_add_security_managers?
    @can_remove_security_managers = authorizer.can_remove_security_managers?

    @visible_security_manager_teams = org_security_managers.teams_visible_to @actor
  end

  def render?
    authorizer.can_view_security_managers?
  end

  def show_osm_v1_dialog?(team)
    # For GHES, we may be able to check when the server was last upgraded
    # however for upgrades after 3.14 we would have no way to know when the
    # machine was upgraded to 3.14. So instead we will just show the dialog
    # for all OSM teams that have read roles assigned to them, and explain
    # to the user that they may need to remove the extra roles.
    if GitHub.enterprise?
      teams_with_read_access.include?(team.id)
    else
      osm_v1_team_ids.include?(team.id)
    end
  end

  memoize def teams_with_read_access
    ids = @visible_security_manager_teams.map(&:id)
    Ability.where(
      actor_type: "Team",
      subject_type: "Repository",
      action: 0, # Read action
      actor_id: ids,
    ).distinct.pluck(:actor_id)
  end

  memoize def osm_v1_team_ids
    roles = UserRole.where(
      actor: @visible_security_manager_teams,
      role: Role.security_manager_role,
      target_id: @organization.id,
      target_type: @organization.user_role_target_type,
    ).where("created_at <= ?", DateTime.new(2024, 5, 24, 5, 40, 0, 0))
    .pluck(:actor_id)
  end

  private

  memoize def org_security_managers
    SecurityProduct::SecurityManagers.new(@organization)
  end

  sig { returns(SecurityProduct::Permissions::OrgAuthz) }
  memoize def authorizer
    SecurityProduct::Permissions::OrgAuthz.new(@organization, actor: @actor)
  end
end
