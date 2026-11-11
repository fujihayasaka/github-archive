# typed: true
# frozen_string_literal: true

class RemoveUnaffiliatedMembersBusinessOrchestration < BusinessOrchestration
  REMOVE_MEMBERS_BATCH_SIZE = 500

  step :check_for_unaffiliated_members do
    return :skipped if user_ids.empty?
  end

  job_start

  step :remove_unaffiliated_members do
    # Process batches of unaffiliated members sequentially
    in_batches(orgs: false, batch_size: REMOVE_MEMBERS_BATCH_SIZE) do |user_ids|
      batch_orchestration = BusinessOrchestration.remove_members(
        business: T.must(business),
        actor: actor,
        user_ids: user_ids,
        reason: "removing unaffiliated users",
        send_notification: true
      )
      batch_orchestration.execute(synchronous: true)
    end
  end

  # Override user_ids intentionally to avoid storing a potentially very large number
  # of IDs in the orchestration record.
  memoize def user_ids
    T.must(business).user_accounts.exclusive_unaffiliated_role.pluck(:user_id)
  end
end
