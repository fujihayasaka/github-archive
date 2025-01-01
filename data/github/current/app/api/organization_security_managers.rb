# typed: true
# frozen_string_literal: true

class Api::OrganizationSecurityManagers < Api::App
  get "/organizations/:organization_id/security-managers", operation_id: "orgs/list-security-manager-teams" do
    control_access :list_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    security_manager_teams = SecurityProduct::SecurityManagers.new(org).teams_visible_to(current_user)
    deliver :team_simple_hash, security_manager_teams, {}
  end

  put "/organizations/:organization_id/security-managers/team/:team_id", operation_id: "orgs/add-security-manager-team" do
    control_access :add_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    SecurityProduct::SecurityManagerRole.grant! team

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/security-managers/team/:team_id", operation_id: "orgs/remove-security-manager-team" do
    control_access :remove_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      SecurityProduct::SecurityManagerRole.revoke! team
    rescue ArgumentError => e
      deliver_error!(400, message: e.message)
    end
    deliver_empty status: 204
  end

  private

  def org
    return @_org if defined?(@_org)
    @_org = find_org!
  end

  def team
    return @_team if defined?(@_team)
    # find_team! uses :org_id by default, but
    # find_org! uses :organization_id
    # So we need to pass :organization_id here so they match since we use both find methods in the same route.
    @_team = find_team!(org_param_name: :organization_id).tap do |team|
      deliver_error!(404) unless team.visible_to? current_user
    end
  end
end
