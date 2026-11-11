# typed: true
# frozen_string_literal: true

class Billing::Zuora::Webhooks::TestHandler < ::Billing::Zuora::Webhooks::WebhookHandler
  # Perform a no-op to test processing
  def perform; end
end
