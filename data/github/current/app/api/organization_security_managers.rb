# typed: true
# frozen_string_literal: true

class Api::OrganizationSecurityManagers < Api::App
  get "/organizations/:organization_id/security-managers", operation_id: "orgs/list-security-manager-teams" do
    deliver_error!(404) if changeset_active?(:close_down_security_managers)
    deprecated(alternate_path_url: "/orgs/{org}/organization-roles/{role_id}/teams")

    control_access :list_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    security_manager_teams = SecurityProduct::SecurityManagers.new(org).teams_visible_to(current_user)
    deliver :team_simple_hash, security_manager_teams, {}
  end

  put "/organizations/:organization_id/security-managers/team/:team_id", operation_id: "orgs/add-security-manager-team" do
    deliver_error!(404) if changeset_active?(:close_down_security_managers)
    deprecated(alternate_path_url: "/orgs/{org}/organization-roles/teams/{team_slug}/{role_id}")

    control_access :add_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    SecurityProduct::SecurityManagerRole.grant_to_team! team

    deliver_empty status: 204
  end

  delete "/organizations/:organization_id/security-managers/team/:team_id", operation_id: "orgs/remove-security-manager-team" do
    deliver_error!(404) if changeset_active?(:close_down_security_managers)
    deprecated(alternate_path_url: "/orgs/{org}/organization-roles/teams/{team_slug}/{role_id}")

    control_access :remove_org_security_managers,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      SecurityProduct::SecurityManagerRole.revoke_from_team! team
    rescue ArgumentError => e
      deliver_error!(400, message: e.message)
    end
    deliver_empty status: 204
  end

  private

  sig { params(alternate_path_url: String).void }
  def deprecated(alternate_path_url:)
    super(
      deprecation_date: Time.utc(2024, 12, 1),
      sunset_date: Time.utc(2026, 1, 1),
      info_url: "https://gh.io/security-managers-rest-api-sunset",
      alternate_path_url:,
    )
  end

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
