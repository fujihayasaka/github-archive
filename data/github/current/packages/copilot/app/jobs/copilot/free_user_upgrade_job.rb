# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserUpgradeJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    BATCH_SIZE = 1_000

    sig { void }
    def perform
      return unless GitHub.flipper[:free_user_upgrade_job].enabled? || noop?
      GitHub.logger.info("Starting FreeUserUpgradeJob")
      Copilot::LimitedUser.select(:id).in_batches(of: BATCH_SIZE) do |batch|
        return if batch.empty?
        batch_ids = batch.pluck(:id)

        batch_first = T.must(batch.first)
        batch_last = T.must(batch.last)

        GitHub.logger.info(
          "Queueing FreeUserUpgradeBatchJob for batch of Copilot Free users",
          "gh.copilot.batch_size" => batch_ids.size,
          "gh.copilot.batch_first_seat_id" => batch_first.id,
          "gh.copilot.batch_last_seat_id" => batch_last.id
        )
        FreeUserUpgradeBatchJob.perform_later(batch_first.id, batch_last.id)
      end
    end

    sig { returns(T::Boolean) }
    def noop?
      GitHub.flipper[:free_user_upgrade_job_noop].enabled?
    end
  end
end
