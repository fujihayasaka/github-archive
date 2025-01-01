# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnforceActiveUserSessionLimitJob < ApplicationJob
  queue_as :enforce_active_user_session_limit

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

  BATCH_LIMIT = 1_000

  # Discard the job if the user is deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(user)
    return unless user.over_active_session_limit?

    GitHub.dogstats.increment("enforce_active_user_session_limit.over_limit.count")

    # user.sessions.user_facing.order("accessed_at DESC").limit(BATCH_LIMIT).pluck(:id)
    ids = user.sessions.user_facing.
      order("accessed_at DESC").
      limit(BATCH_LIMIT).
      # skip the number of sessions that are allowed
      offset(UserSession::LIMIT).
      pluck(:id)

    ActiveRecord::Base.connected_to(role: :writing) do
      ids.each_slice(UserSession::LIMIT) do |session_ids|
        UserSession.throttle do
          UserSession.where(id: session_ids).destroy_all
        end

        GitHub.dogstats.distribution("enforce_active_user_session_limit.sessions_destroyed.count", session_ids.length)
      end
    end

    # If we are still over the limit we requeue another job run to continue
    # pruning old sessions.
    if user.over_active_session_limit?
      EnforceActiveUserSessionLimitJob.perform_later(user)
    end
  end
end
