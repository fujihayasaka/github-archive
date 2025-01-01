# typed: true
# frozen_string_literal: true

module Licensing
  class CheckVssSubscriptionUnprocessedEventsJob < ApplicationJob
    queue_as :licensing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }
    retry_on_dirty_exit
    exempt_from_tenant_context_requirement

    # Public: Report gauge metric of vss subscription events that have not been processed
    #
    # When processing the VSS subscription event received from VSS service bus, we first save the event payload
    # and then queue a job to process the event. This job reports to a gauge in Datadog the number of events that
    # were saved more than 5 minutes ago that are still in the unprocessed state.
    #
    # Returns nothing
    def perform
      unprocessed_events = Licensing::Vss::VssSubscriptionEvent.unprocessed.where("created_at < ?", 5.minutes.ago)
      unprocessed_event_count = unprocessed_events.count

      GitHub.dogstats.gauge("licensing.vss_subscription_unprocessed_events.count", unprocessed_event_count)

      if unprocessed_event_count.positive?
        max_age_in_milliseconds = (Time.now.to_i - unprocessed_events.minimum(:created_at).to_i) * 1000
        GitHub.dogstats.gauge("licensing.vss_subscription_unprocessed_events.max_age", max_age_in_milliseconds)
      end
    end
  end
end
