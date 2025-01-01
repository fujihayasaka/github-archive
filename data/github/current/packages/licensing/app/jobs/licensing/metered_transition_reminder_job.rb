# typed: strict
# frozen_string_literal: true

class Licensing::MeteredTransitionReminderJob < ApplicationJob

  queue_as :licensing
  retry_on_dirty_exit
  exempt_from_tenant_context_requirement
  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  sig { void }
  def perform
    reminders_sent = 0
    Licensing::LicensingModelTransition.scheduled.for_tomorrow.find_each do |transition|
      transition.send_day_before_notice_notification
      reminders_sent += 1
    end

    GitHub.dogstats.count("licensing.metered_transition.reminders", reminders_sent)
  end
end
