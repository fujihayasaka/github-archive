# typed: true
# frozen_string_literal: true

module Licensing
  class CheckVssSubscriptionEventFailuresJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }
    exempt_from_tenant_context_requirement

    before_enqueue do
      throw(:abort) unless GitHub.billing_enabled?
    end

    # Public: Report gauge metric of vss subscription event processing failures
    #
    # When processing the VSS subscription event received from VSS service bus, the processing might fail
    # which is recorded in the Licensing::Vss::VssSubscriptionEvent. This job reports to a gauge in Datadog when the
    # about the failures.
    #
    # Returns nothing
    def perform
      failed_vss_subscription = Licensing::Vss::VssSubscriptionEvent.failed
      failed_vss_subscription_count = failed_vss_subscription.count

      GitHub.dogstats.gauge("licensing.vss_subscription_event_failures.count", failed_vss_subscription_count)

      if failed_vss_subscription_count.positive?
        max_age_in_milliseconds = (Time.now.to_i - failed_vss_subscription.minimum(:created_at).to_i) * 1000
        GitHub.dogstats.gauge("licensing.vss_subscription_event_failures.max_age", max_age_in_milliseconds)
      end
    end
  end
end
