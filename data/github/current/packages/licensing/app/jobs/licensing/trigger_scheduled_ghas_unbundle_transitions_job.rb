# typed: strict
# frozen_string_literal: true

module Licensing
  class TriggerScheduledGhasUnbundleTransitionsJob < ApplicationJob

    queue_as :licensing
    retry_on_dirty_exit
    schedule interval: 15.minutes, condition: -> { GitHub.billing_enabled? }
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      scheduled_transitions = Licensing::GhasUnbundleTransition.for_today.scheduled
      GitHub.dogstats.increment "licensing.trigger_scheduled_ghas_unbundle_transitions.count", by: scheduled_transitions.count

      scheduled_transitions.find_each do |transition|
        with_write { transition.enqueue }
      end
    end
  end
end
