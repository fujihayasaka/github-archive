# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedUserCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
    resolve_tenant_context do |user_id|
      ::User.find_by(id: user_id)&.enterprise_managed_business
    end

    sig { params(user_id: Integer).void }
    def perform(user_id)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.user.id" => user_id) do
        limited_user = Copilot::LimitedUser.find_by(user_id: user_id)

        if limited_user.nil?
          GitHub.logger.info "No limited user found"
          GitHub.dogstats.increment("copilot.free_user_cleanup_job.limited_user_not_found")
          return
        end

        if limited_user.user.present?
          GitHub.logger.info "User is still present"
          GitHub.dogstats.increment("copilot.free_user_cleanup_job.limited_user_still_present")
          return
        end

        GitHub.dogstats.increment("copilot.free_user_cleanup_job.limited_user_deleted")
        GitHub.logger.info "Deleting limited user", "gh.copilot.limited_user.id" => limited_user.id

        with_write do
          limited_user.destroy!
        end
      end
    end
  end
end
