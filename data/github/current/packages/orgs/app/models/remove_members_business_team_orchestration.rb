# typed: true
# frozen_string_literal: true

class RemoveMembersBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  step :bulk_remove_team_members do
    options = data[:options] || {}
    result = T.must(business_team).bulk_remove_members(users: users, force: options[:force], send_notification: options[:send_notification], team_destroyed: options[:team_destroyed], queue_delete_jobs: options[:queue_delete_jobs], caller_type: :business_team, called_from_orchestration: true)
    data[:result] = result
  end

  job_start

  step :clear_business_team_indirect_org_access do
    ClearBusinessTeamIndirectOrgAccessJob.enqueue(
      business_id: business_id,
      team_id: team_id,
      clear_team_roles: false,
      user_ids: user_ids,
      organization_ids: T.must(business_team).organization_ids
    )
  end
end
