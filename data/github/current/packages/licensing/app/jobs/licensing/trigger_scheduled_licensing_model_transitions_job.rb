# typed: strict
# frozen_string_literal: true

module Licensing
  class TriggerScheduledLicensingModelTransitionsJob < ApplicationJob
    queue_as :licensing
    retry_on_dirty_exit
    schedule interval: 15.minutes, condition: -> { GitHub.billing_enabled? }
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      scheduled_transitions = LicensingModelTransition.for_today.scheduled
      stale_queued_transitions = LicensingModelTransition.for_today.stale_queued

      transitions = scheduled_transitions.or(stale_queued_transitions)
      GitHub.dogstats.increment "licensing.trigger_scheduled_licensing_model_transitions.count", by: transitions.count

      transitions.find_each do |transition|
        with_write { transition.enqueue }
      end
    end
  end
end
