# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    sig { params(user_id: Integer).void }
    def perform(user_id)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.user.id" => user_id) do
        free_user = Copilot::FreeUser.find_by(user_id: user_id)

        if free_user.nil?
          GitHub.logger.info "No free user found"
          GitHub.dogstats.increment("copilot.free_user_cleanup_job.free_user_not_found")
          return
        end

        if free_user.user.present?
          GitHub.logger.info "User is still present"
          GitHub.dogstats.increment("copilot.free_user_cleanup_job.free_user_still_present")
          return
        end

        GitHub.dogstats.increment("copilot.free_user_cleanup_job.free_user_deleted")
        GitHub.logger.info "Deleting free user", "gh.copilot.free_user.id" => free_user.id

        with_write do
          free_user.destroy!
        end
      end
    end
  end
end
