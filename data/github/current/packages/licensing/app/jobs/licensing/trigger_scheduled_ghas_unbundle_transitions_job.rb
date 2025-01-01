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
      Licensing::GhasUnbundleTransition.for_today.each do |transition|
        # do not refire a job that has already been picked up
        next unless transition.status == "scheduled"

        GitHub.dogstats.increment "licensing.trigger_scheduled_ghas_unbundle_transition"

        with_write do
          transition.enqueue
        end
      end
    end
  end
end
