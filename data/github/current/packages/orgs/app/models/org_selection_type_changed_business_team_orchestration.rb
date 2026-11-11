# typed: true
# frozen_string_literal: true

class OrgSelectionTypeChangedBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  job_start

  step :send_org_selection_type_changed_notifications do
    team = T.must(business_team)
    previous_type = data[:previous_organization_selection_type]
    current_type = team.organization_selection_type
    business_object = T.must(business)

    if current_type == "all" && previous_type != "all"
      orgs = business_object.organizations.to_a
      return if orgs.empty?

      send_org_added_emails(
        orgs: orgs,
        business: business_object,
        team: team,
        notify_actor: actor,
        member_count: team.members_scope_count
      )
    elsif current_type == "disabled" && previous_type == "all"
      orgs = business_object.organizations.to_a
      return if orgs.empty?

      send_org_removed_emails(
        orgs: orgs,
        org_count: orgs.size,
        business: business_object,
        team: team
      )
    elsif current_type == "disabled" && previous_type == "selected"
      send_org_removed_emails(
        orgs: [],
        org_count: "all",
        business: business_object,
        team: team
      )
    end
  end

  step :instrument_business_team_enablement_toggled do
    return if GitHub.single_business_environment?

    GlobalInstrumenter.instrument("business_team.enablement_toggled", {
      consuming_license: T.must(business_team).organization_selection_type != "disabled" && T.must(business_team).has_any_orgs?,
      business_team: T.must(business_team),
    })
  end

  step :instrument_business_team_org_assignments do
    return if GitHub.single_business_environment?

    team = T.must(business_team)
    previous_type = data[:previous_organization_selection_type]
    current_type = team.organization_selection_type

    if current_type == "all" && previous_type != "all"
      # Team is now assigned to all orgs
      GlobalInstrumenter.instrument("business_team.assigned_to_all_organizations", {
        business_id: team.business_id,
        business_team_id: team.id,
      })
    elsif previous_type == "all" && current_type != "all"
      # Team is no longer assigned to all orgs
      GlobalInstrumenter.instrument("business_team.unassigned_from_all_organizations", {
        business_id: team.business_id,
        business_team_id: team.id,
      })
    end
  end

  step :synchronize_member_search_indexes do
    SynchronizeBusinessTeamMembersSearchIndexJob.perform_later(team_ids: [team_id])
  end
end
