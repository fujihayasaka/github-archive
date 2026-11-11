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

  step :send_added_notifications do
    return unless data[:result] == :success

    options = data[:options] || {}
    team = T.must(business_team)
    business = T.must(team.business)

    users.each do |user|
      if !user.suspended? && options[:send_notification] != false
        BusinessTeamsMailer.added_to_team(user, business, team).deliver_later
      end
    end
  end

  step :update_business_user_accounts do
    return if GitHub.single_business_environment?
    T.must(business_team).update_buas(user_ids)
  end

  step :synchronize_member_search_indexes do
    return unless T.must(business_team).has_any_orgs?

    SynchronizeBusinessTeamMembersSearchIndexJob.perform_later(team_ids: [team_id], user_ids: T.must(user_ids))
  end
end
