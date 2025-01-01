# typed: strict
# frozen_string_literal: true

module Copilot
  # This job is used specifically when a FreeUser's trial is expiring as a result
  # of calling FreeUser#warn_and_queue_cancel!
  class FreeUserCancellationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    sig { params(copilot_free_user_id: Integer).void }
    def perform(copilot_free_user_id)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.free_user.id" => copilot_free_user_id) do
        free_user = Copilot::FreeUser.find_by(id: copilot_free_user_id)

        if free_user.nil?
          GitHub.logger.info("Free User not found")
          GitHub.dogstats.increment("copilot.free_user_cancellation_job.free_user_not_found")
          return
        end

        if free_user.user.present?
          GitHub.logger.info("Canceling free user", "gh.user.id" => free_user.user_id)
          GitHub.dogstats.increment("copilot.free_user_cancellation_job.free_user_cancelled")

          with_write do
            free_user.cancel!
          end
        else
          # if the user has been deleted, we can't/won't send them an email
          GitHub.logger.info("Deleting free user", "gh.user.id" => free_user.user_id)
          GitHub.dogstats.increment("copilot.free_user_cancellation_job.free_user_deleted")

          with_write do
            free_user.destroy!
          end
        end
      end
    end
  end
end
