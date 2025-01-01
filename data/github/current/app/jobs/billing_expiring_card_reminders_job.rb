# typed: true
# frozen_string_literal: true

class BillingExpiringCardRemindersJob < BillingJob
  queue_as :billing

  schedule interval: 1.week, condition: -> { !GitHub.enterprise? }

  exempt_from_tenant_context_requirement

  def perform
    PaymentMethod.send_expiring_credit_card_reminders
  end
end
