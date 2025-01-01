# typed: strict
# frozen_string_literal: true

# This class will be run on a weekly schedule.  It iterates over the 34 languages in COPILOT_ENGAGED_OSS_LANGUAGES
# and calls Copilot::EngagedOssLanguageJob for each language
module Copilot
  class EngagedOssJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 7.days, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_engaged_oss_job

    sig { void }
    def perform
      chatterbox_say("Starting Copilot::EngagedOssJob")
      waiting_period = T.let(0.minutes, ActiveSupport::Duration)

      Copilot::COPILOT_ENGAGED_OSS_LANGUAGES.each_with_index do |language, index|
        waiting_period = index.minutes
        GitHub.logger.info(
          "Scheduling Engaged OSS Language job",
          "gh.programming_language" => language,
          "gh.job.waiting_period" => waiting_period,
        )

        Copilot::EngagedOssLanguageJob.perform_after_waiting_period(
          waiting_period,
          language: language,
        )
      end

      # send for no languages
      Copilot::EngagedOssLanguageJob.perform_after_waiting_period(
        waiting_period,
        language: nil,
      )
      chatterbox_say("Finished Copilot::EngagedOssJob")
    end
  end
end
