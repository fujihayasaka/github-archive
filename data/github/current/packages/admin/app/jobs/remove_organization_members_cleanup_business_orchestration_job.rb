# typed: strict
# frozen_string_literal: true

class RemoveOrganizationMembersCleanupBusinessOrchestrationJob < BusinessOrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  LOCK_TTL = T.let(120.minutes, Integer)
  GLOBAL_LOCK_KEY = T.let("remove_organization_members_cleanup_business_orchestration_job", String)

  # Retry for less than an hour, after 1 hour, the sweeper will restart the job so unlimited attempts would just make the queue grow
  RETRY_WAIT_TIME = T.let(15.minutes, Integer)
  ATTEMPTS = T.let(3, Integer)

  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_WAIT_TIME, attempts: ATTEMPTS, jitter: 0.3

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(GLOBAL_LOCK_KEY, GitHub.business_team_org_remove_member_job_limit, LOCK_TTL) do
      block.call
    end
  end
end
