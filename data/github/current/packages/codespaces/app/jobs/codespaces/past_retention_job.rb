# typed: true
# frozen_string_literal: true

class Codespaces::PastRetentionJob < CodespacesJob
  retry_on_dirty_exit
  schedule interval: 1.minute, condition: -> { !GitHub.enterprise? }

  def perform
    return if FeatureFlag.vexi.enabled_or_raise?(:disable_past_retention_job) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    Codespace.past_retention.includes(:owner).limit(1000).each do |codespace|
      with_write do
        Codespace.throttle_with_retry { codespace.deprovision!(reason: Codespace.deletion_reasons[:retention_period]) }
      rescue => e # rubocop:todo Lint/RescueException
        Codespaces::ErrorReporter.report(e, codespace: codespace)
        next
      end
    end
  end
end
