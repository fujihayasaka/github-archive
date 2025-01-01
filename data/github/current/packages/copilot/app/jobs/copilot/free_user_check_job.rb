# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 20.minutes, key: DEFAULT_LOCK_PROC
    schedule interval: 3.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_free_user_check_job

    sig { void }
    def perform
      chatterbox_say("Starting Copilot::FreeUserCheckJob")

      GitHub.logger.with_named_tags("code.function" => "perform") do
        GitHub.logger.info("Starting Copilot free user check job")

        # load up unsubscribed free users older than 24 hours
        unsubscribed = with_read do
          Copilot::FreeUser.not_subscribed
        end

        GitHub.logger.info("Loaded unsubscribed free users", "gh.copilot.free_user.unsubscribed.count" => unsubscribed.count)

        if unsubscribed.any?
          GitHub.logger.info("Deleting unsubscribed free users", "gh.copilot.free_user.unsubscribed.count" => unsubscribed.count)
          with_write do
            Copilot::FreeUser.not_subscribed.delete_all
          end
        end

        GitHub.dogstats.histogram("copilot.free_user_check_job.unsubscribed_free_users", unsubscribed.count)

        to_update = with_read do
          Copilot::FreeUser.needs_updating
        end

        GitHub.logger.info("Loaded free users to update", "gh.copilot.free_user.to_update.count" => to_update.count)

        if to_update.any?
          GitHub.logger.info("Updating free users", "gh.copilot.free_user.to_update.count" => to_update.count)

          to_update.each do |free_user|
            Copilot::FreeUserProcessorJob.perform_later(free_user.id)
          end
        end

        GitHub.dogstats.histogram("copilot.free_user_check_job.free_users_to_update", to_update.count)

        message = <<~HEREDOC
          FreeUserCheckJob Completed
          Free Users Updated: #{to_update.count}
          Free Users Unsubscribed: #{unsubscribed.count}
        HEREDOC

        chatterbox_say(message)

        GitHub.logger.info("Finished Copilot free user check job")
      end
    end
  end
end
