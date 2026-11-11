# typed: true
# frozen_string_literal: true

class AddMembersBusinessTeamOrchestration < TeamOrchestration
  include GitHub::Memoizer

  step :bulk_add_team_members do
    options = data[:options] || {}
    result = T.must(business_team).bulk_add_members(users.to_a, options.merge(called_from_orchestration: true))
    data[:result] = result.status
  end

  step :add_member_roles do
    if data[:options] && data[:options][:has_orgs] == true
      T.must(business_team).add_member_role(T.must(user_ids))
    end
  end

  job_start

  step :update_business_user_accounts do
    return if GitHub.single_business_environment?
    T.must(business_team).update_buas(user_ids)
  end
end
