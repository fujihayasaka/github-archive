# typed: true
# frozen_string_literal: true

# Handler for AccountUpdated webhooks from Zuora
class Billing::Zuora::Webhooks::AccountUpdated < Billing::Zuora::Webhooks::WebhookHandler
  T.unsafe(self).before_perform :ignore!, if: :account_deleted_or_suspended?

  def perform
    customer.update_from_zuora
  end
end
