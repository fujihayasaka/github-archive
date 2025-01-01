# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeamOrganizations < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi

  sig { returns(T::Hash[Symbol, String]) }
  def base_error_config
    { documentation_url: "https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/articles/rest-api-endpoints-for-enterprise-teams" }
  end

  MAX_ORGANIZATIONS_PER_OPERATION = 100

  post "/enterprises/:enterprise_id/teams/:team_id/organizations/add", operation_id: "enterprise-team-organizations/bulk-add", read_from_replicas: true do
    enterprise = find_enterprise!(error_options: base_error_config)
    deliver_error! 404, **base_error_config unless BusinessTeam.enabled_for_enterprise?(business: enterprise)
    deliver_error! 404, **base_error_config unless enterprise.erp_feature_enabled?(:enterprise_teams_org_api)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    unless team.organization_selection_type == "selected"
      deliver_error! 422, **base_error_config, message: "The team's organization selection type must be set to selected"
    end

    data = receive(Hash)
    organization_slugs = data.fetch("organization_slugs", [])
    if !organization_slugs.is_a?(Array) || organization_slugs.empty?
      deliver_error! 400, **base_error_config, message: "Missing organization_slugs"
    end

    if organization_slugs.count > MAX_ORGANIZATIONS_PER_OPERATION
      deliver_error! 400, **base_error_config, message: "Too many organization_slugs"
    end

    business_id = if GitHub.multi_tenant_enterprise?
      enterprise.id
    else
      0 # in all other environments, an org's business_id is always 0
    end
    if team.organizations.where(display_login: organization_slugs, business_id: business_id).any?
      deliver_error! 400, **base_error_config, message: "Team already assigned to one or more organizations"
    end

    orgs = enterprise.organizations.where(display_login: organization_slugs)
    unless orgs.count == organization_slugs.count
      deliver_error! 400, **base_error_config, message: "One or more organization does not exist or does not belong to the enterprise"
    end

    if orgs.count + team.organizations.count > team.limit_organization_assignments
      deliver_error! 400, **base_error_config, message: "Cannot assign business team to organizations because it will exceed the assignment limit"
    end

    status = with_write do
      team.add_to_organizations(org_ids: orgs.pluck(:id))
    end
    if status.error?
      deliver_error! 422, **base_error_config, message: status.message
    end

    deliver :organization_hash, orgs, status: 200
  end
end
