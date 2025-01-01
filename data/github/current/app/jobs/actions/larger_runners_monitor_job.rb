# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Actions
  class LargerRunnersMonitorJob < ApplicationJob

    schedule interval: 24.hours, condition: -> { GitHub.actions_larger_runners_enabled? }

    queue_as :actions_pools_usage_monitoring_job

    # This error will be raised when 0 actors returned for FF. We need to know about it, because it means FF is enabled globally now and this job is not working as expected anymore.
    # Ticket to develop a better monitoring approach before that: https://github.com/github/c2c-actions-larger-runners/issues/1147
    rescue_from(ArgumentError) do |exception|
      Failbot.report(exception)
    end

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform
      return if FeatureFlag.vexi.enabled_or_raise?(:disable_monitor_custom_hosted_pools_job) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      Configurable::ActionsLargerRunnersOnboarding.larger_runners_onboarded_businesses.find_each do |bus|
        # Don't iterate by organizations inside business because they are included to larger_runners_onboarded_organizations
        UpdateNonUsedCustomPoolsJob.set(wait: jitter).perform_later(entity: bus)
      end

      Configurable::ActionsLargerRunnersOnboarding.larger_runners_onboarded_organizations.find_each do |org|
        UpdateNonUsedCustomPoolsJob.set(wait: jitter).perform_later(entity: org)
      end
    end

    def jitter
      # This job runs once a day and results aren't required to be immediate, so spread
      # the jobs out. See https://github.com/github/actions-larger-runners/issues/1505
      rand(4.hours)
    end
  end
end
