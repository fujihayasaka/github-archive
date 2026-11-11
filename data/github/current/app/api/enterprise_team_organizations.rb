# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeamOrganizations < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi

  MAX_ORGANIZATIONS_PER_OPERATION = 100

  get "/enterprises/:enterprise_id/teams/:team_id/organizations/:org", operation_id: "enterprise-team-organizations/get-assignment", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    org = find_org!
    if team.is_associated_with_organization?(org)
      deliver :organization_hash, org, status: 200
    else
      deliver_error! 404, message: "The team is not assigned to that organization"
    end
  end

  get "/enterprises/:enterprise_id/teams/:team_id/organizations", operation_id: "enterprise-team-organizations/get-assignments", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    orgs = paginate_rel(team.organizations.includes(:profile).order(:login))
    deliver :organization_hash, orgs, status: 200
  end

  delete "/enterprises/:enterprise_id/teams/:team_id/organizations/:org", operation_id: "enterprise-team-organizations/delete", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    org = find_org!
    deliver_error! 422, message: "The team's organization selection type must be set to selected" unless team.organization_selection_type == "selected"
    deliver_error! 400, message: "The organization does not belong to the same enterprise as the team" unless org.business.id == enterprise.id
    deliver_error! 400, message: "The team is not assigned to that organization" unless team.is_associated_with_organization?(org)

    team.remove_from_organizations(org_ids: [org.id])
    deliver_empty status: 204
  end

  put "/enterprises/:enterprise_id/teams/:team_id/organizations/:org", operation_id: "enterprise-team-organizations/add", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    org = find_org!
    deliver_error! 422, message: "The team's organization selection type must be set to selected" unless team.organization_selection_type == "selected"
    deliver_error! 400, message: "The organization does not belong to the same enterprise as the team" unless org.business.id == enterprise.id
    deliver_error! 400, message: "The team is already assigned to that organization" if team.organizations.where(id: org.id, business_id: organization_business_id(enterprise)).any?
    if team.organizations.count + 1 > team.organization_assignments_limit
      deliver_error! 400, message: "Cannot assign the team to another organization because it will exceed the assignment limit of #{team.organization_assignments_limit}"
    end

    status = with_write do
      team.add_to_organizations(org_ids: [org.id])
    end
    if status.error?
      deliver_error! 422, message: status.message
    end

    deliver :organization_hash, org, status: 201
  end

  post "/enterprises/:enterprise_id/teams/:team_id/organizations/add", operation_id: "enterprise-team-organizations/bulk-add", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    organization_slugs = get_organization_slugs_from_body!
    deliver_error! 422, message: "The team's organization selection type must be set to selected" unless team.organization_selection_type == "selected"
    if organization_slugs.count + team.organizations.count > team.organization_assignments_limit
      deliver_error! 400, message: "Cannot assign enterprise team to organizations because it will exceed the assignment limit of #{team.organization_assignments_limit}"
    end

    already_assigned_orgs = team.organizations.where(display_login: organization_slugs, business_id: organization_business_id(enterprise))
    if already_assigned_orgs.any?
      errors = already_assigned_orgs.map do |org|
        "The team is already assigned to #{org.display_login}"
      end
      deliver_error! 400, message: "Team already assigned to one or more organizations", errors: errors
    end

    orgs = enterprise.organizations.where(display_login: organization_slugs)
    unless orgs.count == organization_slugs.count
      missing_org_logins = orgs.pluck(:display_login) - organization_slugs
      errors = missing_org_logins.map do |org_login|
        "#{org_login} does not exist or does not belong to the enterprise"
      end
      deliver_error! 400, message: "One or more organization does not exist or does not belong to the enterprise", errors: errors
    end

    status = with_write do
      team.add_to_organizations(org_ids: orgs.pluck(:id))
    end
    if status.error?
      deliver_error! 422, message: status.message
    end

    deliver :organization_hash, orgs, status: 200
  end

  post "/enterprises/:enterprise_id/teams/:team_id/organizations/remove", operation_id: "enterprise-team-organizations/bulk-remove", read_from_replicas: true do
    enterprise = find_enterprise!
    check_enabled!(enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = find_business_team!
    organization_slugs = get_organization_slugs_from_body!
    deliver_error! 422, message: "The team's organization selection type must be set to selected" unless team.organization_selection_type == "selected"
    orgs = team.organizations.where(display_login: organization_slugs, business_id: organization_business_id(enterprise))
    if orgs.count != organization_slugs.count
      unassigned_org_logins = orgs.pluck(:display_login) - organization_slugs
      errors = unassigned_org_logins.map do |org_login|
        "The team is not assigned to #{org_login}"
      end
      deliver_error! 400, message: "The team is not assigned to one or more organizations", errors: errors
    end

    team.remove_from_organizations(org_ids: orgs.pluck(:id))
    deliver_empty status: 204
  end

  private

  sig { params(enterprise: Business).returns(Integer) }
  def organization_business_id(enterprise)
    if GitHub.multi_tenant_enterprise?
      enterprise.id
    else
      0 # in all other environments, an org's business_id is always 0
    end
  end

  sig { params(enterprise: Business).void }
  def check_enabled!(enterprise)
    # not enabled if ETv1 is enabled instead of ETv2
    deliver_error! 404 unless BusinessTeam.enabled_for_enterprise?(business: enterprise)
  end

  sig { returns(T::Array[String]) }
  def get_organization_slugs_from_body!
    data = receive(Hash)
    organization_slugs = data.fetch("organization_slugs", [])
    deliver_error! 400, message: "Missing organization_slugs" if !organization_slugs.is_a?(Array) || organization_slugs.empty?
    deliver_error! 400, message: "Too many organization_slugs, try again with #{MAX_ORGANIZATIONS_PER_OPERATION} or fewer" if organization_slugs.count > MAX_ORGANIZATIONS_PER_OPERATION

    organization_slugs
  end
end
