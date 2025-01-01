# typed: true
# frozen_string_literal: true

class RemoveOrganizationsBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  BATCH_SIZE = 100

  step :remove_from_organizations do
    with_write { BusinessTeamOrgAssignment.where(team_id: team_id, organization_id: organization_ids).destroy_all }
  end

  job_start

  step :instrument_remove_from_organization do
    return unless business&.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
    T.must(organization_ids).each_slice(BATCH_SIZE) do |organization_ids_batch|
      Organization.where(id: organization_ids_batch).each do |organization|
        T.must(business_team).instrument :remove_from_organization, org: organization, business: business
      end
    end
  end

  step :instrument_business_team_enablement_toggled do
    return if GitHub.single_business_environment?
    return if T.must(business_team).has_any_orgs?

    GlobalInstrumenter.instrument("business_team.enablement_toggled", {
      consuming_license: false,
      business_team: T.must(business_team),
    })
  end

  step :update_business_user_accounts do
    return if GitHub.single_business_environment?
    T.must(business_team).update_buas
  end

  step :clear_business_team_indirect_org_access do
    ClearBusinessTeamIndirectOrgAccessJob.enqueue(
      business_id: business_id,
      team_id: team_id,
      clear_team_roles: true,
      organization_ids: organization_ids
    )
  end
end
