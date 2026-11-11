# typed: true
# frozen_string_literal: true

class AddOrganizationsBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  BATCH_SIZE = 100

  step :add_to_organizations do
    data[:organization_assignments_count_was] = T.must(business_team).organization_assignments_limit_counter

    member_ids = T.must(business_team).member_ids
    first_org_assignment = member_ids.any? && !T.must(business_team).business_team_org_assignments.exists?
    T.must(organization_ids).map do |org_id|
      {
        team_id: team_id,
        organization_id: org_id,
        business_id: business_id,
      }
    end.each_slice(BusinessTeam::BATCH_SIZE) do |batch|
      T.must(business).raise_if_kill_switch_enabled!("business_team.add_to_organizations",
        feature_flag: :enterprise_teams_killswitch,
        log_fields: { "gh.team.id": team_id },
      )

      with_write do
        BusinessTeamOrgAssignment.throttle do
          BusinessTeamOrgAssignment.insert_all(batch)
        end
      end
    end

    if first_org_assignment
      T.must(business_team).add_member_role(member_ids)
    end
  end

  job_start

  step :instrument_add_to_organization do
    return if data[:skip_instrumentation]
    T.must(organization_ids).each_slice(BATCH_SIZE) do |organization_ids_batch|
      Organization.where(id: organization_ids_batch).each do |organization|
        T.must(business_team).instrument :add_to_organization, org: organization, business: business
        # Publish GlobalInstrumenter event for Hydro subscription
        GlobalInstrumenter.instrument("business_team.add_to_organization", {
          business_team: T.must(business_team),
          org: organization,
          business: business,
        })
      end

      GlobalInstrumenter.instrument("business_team.add_to_organizations", {
        business_team: T.must(business_team),
        organization_ids: organization_ids_batch,
        business: business,
      })
    end
  end

  step :instrument_organization_assignments_limit_events do
    return if data[:organization_assignments_count_was].nil?

    T.must(business_team).instrument_organization_assignments_limit_events(
      organization_assignments_count_was: data[:organization_assignments_count_was]
    )
  end

  step :send_organization_assignments_limit_notifications do
    return if data[:organization_assignments_count_was].nil?

    T.must(business_team).send_organization_assignments_limit_notifications(
      organization_assignments_count_was: data[:organization_assignments_count_was]
    )
  end

  step :instrument_business_team_enablement_toggled do
    return if GitHub.single_business_environment?
    GlobalInstrumenter.instrument("business_team.enablement_toggled", {
      consuming_license: true,
      business_team: T.must(business_team),
    })
  end

  step :update_business_user_accounts do
    return if GitHub.single_business_environment?
    T.must(business_team).update_buas
  end
end
