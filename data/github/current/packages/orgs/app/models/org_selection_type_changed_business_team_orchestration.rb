# typed: true
# frozen_string_literal: true

class OrgSelectionTypeChangedBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  job_start

  step :instrument_business_team_enablement_toggled do
    return if GitHub.single_business_environment?

    GlobalInstrumenter.instrument("business_team.enablement_toggled", {
      consuming_license: T.must(business_team).organization_selection_type != "disabled" && T.must(business_team).has_any_orgs?,
      business_team: T.must(business_team),
    })
  end
end
