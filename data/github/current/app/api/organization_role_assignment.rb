# typed: true
# frozen_string_literal: true

class Api::OrganizationRoleAssignment < Api::App
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/organization-roles/:role_id/users", operation_id: "orgs/list-org-role-users" do
    org = find_org!

    role = find_org_role!

    control_access :read_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    assignment_data = RoleAssignmentList::OrgRoleAssignments.new(organization: org, actor_type: "User", direct_only: false, role_ids: [role.id])
    paginated_assignees = paginate_rel(assignment_data.assignees)

    assignments = assignment_data.assignments.group_by { |a| T.must(a.actor.id) }
    deliver :user_role_assignment_hash, { users: paginated_assignees, assignments: assignments, total_count: paginated_assignees.total_entries }
  end

  get "/organizations/:organization_id/organization-roles/:role_id/teams", operation_id: "orgs/list-org-role-teams" do
    org = find_org!

    role = find_org_role!

    control_access :read_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    org_role_assignments = RoleAssignmentList::OrgRoleAssignments.new(organization: org, actor_type: "Team", direct_only: false, role_ids: [role.id])
    paginated_teams = paginate_rel(org_role_assignments.assignees)

    assignments = org_role_assignments.assignments.group_by { |a| T.must(a.actor.id) }

    GitHub::PrefillAssociations.prefill_associations(paginated_teams, { organization: :profile })
    GitHub::PrefillAssociations.prefill_associations(paginated_teams, :ldap_mapping) if GitHub.enterprise?

    deliver :team_role_assignment_hash, { teams: paginated_teams, assignments: assignments, total_count: paginated_teams.total_entries }
  end

  put "/organizations/:organization_id/organization-roles/users/:username/:role_id", operation_id: "orgs/assign-user-to-org-role" do
    org, user = find_org!, this_user

    role = find_org_role!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    if user.organization?
      deliver_error! 422, message: "Assignees must be users, not organizations."
    end

    unless org.member?(user)
      deliver_error! 422, message: "User #{user.login_for_api} needs to be member of #{org.login_for_api} before assigning an organization role."
    end

    result = org.grant_org_role(assignee: user, role: role)

    unless result.success?
      deliver_error! 500, message: "Failed to grant role #{role.name} to user #{user.login_for_api}."
    end

    deliver_empty status: 204
  end

  put "/organizations/:organization_id/organization-roles/team/:team_id/:role_id", operation_id: "orgs/assign-team-to-org-role" do
    org  = find_org!
    team = find_team!

    role = find_org_role!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    deliver_error!(404) unless team.visible_to? current_user

    result = org.grant_org_role(assignee: team, role: role)

    unless result.success?
      deliver_error! 500, message: "Failed to grant role #{role.name} to user #{team}."
    end

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/organization-roles/users/:username/:role_id", operation_id: "orgs/revoke-org-role-user" do
    org = find_org!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    role = find_org_role!

    user = this_user

    if user.organization?
      deliver_error! 422, message: "Only users are supported: #{user.login_for_api} is an organization."
    end

    unless org.member?(user)
      deliver_error! 422, message: "User #{user.login_for_api} is not a member of #{org.login_for_api}."
    end

    result = org.revoke_org_role(assignee: user, role: role)
    unless result.success?
      deliver_error! 400, message: "Failed to revoke role #{role.name} from user: #{user.login_for_api}."
    end

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/organization-roles/team/:team_id/:role_id", operation_id: "orgs/revoke-org-role-team" do
    org = find_org!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    team = find_team!
    deliver_error!(404) unless team.visible_to? current_user

    role = find_org_role!

    result = org.revoke_org_role(assignee: team, role: role)
    unless result.success?
      deliver_error! 400, message: "Failed to revoke role #{role.name} from team: #{team}."
    end

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/organization-roles/users/:username", operation_id: "orgs/revoke-all-org-roles-user" do
    org = find_org!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    user = this_user

    if user.organization?
      deliver_error! 422, message: "Only users are supported: #{user.login_for_api} is an organization."
    end

    unless org.member?(user)
      deliver_error! 422, message: "User #{user.login_for_api} is not a member of #{org.login_for_api}."
    end

    result = org.revoke_all_org_roles(assignee: user)
    unless result.success?
      deliver_error! 400, message: "Failed to revoke all roles from user: #{user.login_for_api}."
    end

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/organization-roles/team/:team_id", operation_id: "orgs/revoke-all-org-roles-team" do
    org = find_org!

    control_access :manage_org_role_assignments,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

    team = find_team!
    deliver_error!(404) unless team.visible_to? current_user

    result = org.revoke_all_org_roles(assignee: team)
    unless result.success?
      deliver_error! 400, message: "Failed to revoke all roles from team: #{team}."
    end

    deliver_empty status: 204
  end

  private

  def find_team(param_name: :team_id, org_param_name: :organization_id, with_business_teams: true)
    # If the team was found and cached in the router, use that to save
    # lookups.
    found_team = env[GitHub::Routers::Api::ThisTeamKey] || super

    if found_team.is_a?(BusinessTeam)
      business = found_team.business

      # Unset the found_team if the feature flag does not permit returning the BusinessTeam.
      if business.nil? || !business.erp_feature_enabled?(:enterprise_teams_org_roles)
        found_team = nil
      end
    end

    found_team
  end
end
