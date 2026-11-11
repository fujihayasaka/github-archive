# typed: strict
# frozen_string_literal: true

require "chatterbox-client"

module Billing
  module Azure
    class SendInvalidSubscriptionNotificationJob < BillingJob
      retry_on(Chatterbox::Error, wait: :polynomially_longer, attempts: 10) do |_job, error|
        GitHub.dogstats.increment("billing.azure.spam_slam.slack_notification_failed")
        Failbot.report(error)
      end

      sig { params(customer_id: Integer).void }
      def perform(customer_id:)
        customer = ::Customer.find_by(id: customer_id)
        return unless customer

        with_write { InvalidSubscriptionSlackNotifier.new(customer:).send_notification }
      end
    end
  end
end
