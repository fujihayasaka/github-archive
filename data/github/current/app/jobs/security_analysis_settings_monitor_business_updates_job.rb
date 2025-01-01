# typed: true
# frozen_string_literal: true

class SecurityAnalysisSettingsMonitorBusinessUpdatesJob < ApplicationJob
  include SecretScanning::Features::FeatureFlagHelper

  queue_as :security_analysis_settings_monitor_business_updates
  retry_on_dirty_exit

  def perform(owner:, update_type:, duration: 15)
    if BlockedSettings.new(owner).include?(update_type)
      GitHub.logger.info("Queuing next job to run after #{duration}-second delay", "code.namespace": self.class.name, "code.function": __method__)
      SecurityAnalysisSettingsMonitorBusinessUpdatesJob
        .set(wait: duration.seconds)
        .perform_later(owner: owner, update_type: update_type, duration: duration)
      GitHub.dogstats.increment("security_analysis_settings_monitor_business_updates_job.schedule_next")
      return
    end

    GitHub.logger.info("Sending backfill group request", "code.namespace": self.class.name, "code.function": __method__)
    GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
      owner: owner,
      action: update_type == :secret_scanning_enable_all ? :START : :CANCEL,
      type: :FULL,
      requested_at: Time.now.utc,
      feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags
    })
  end
end
