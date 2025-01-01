# typed: true
# frozen_string_literal: true

module Billing
  class InvoicedMeteredBillingSlackNotifier
    THRESHOLD_NOTIFICATION_SLACK_CHANNEL = "#invoiced-metered-billing-threshold-ops"

    def initialize(owner:, paid:, usage_message:)
      @owner = owner
      @paid = paid
      @usage_message = usage_message
    end

    # Send notification to sales slack channel for invoiced customers
    def send_notification
      GitHub::Chatterbox.client.say(THRESHOLD_NOTIFICATION_SLACK_CHANNEL, message)
    end

    private

    attr_reader :owner, :paid, :usage_message

    def message
      "[#{paid ? "Paid" : "Included Free"} Usage Alert] " \
      "<https://admin.github.com#{stafftools_path(owner)}|#{owner.name}> " \
      "#{usage_message}\n#{meter_reset_date}"
    end

    def meter_reset_date
      "Meter resets on: #{owner.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
    end

    def stafftools_path(owner)
      if owner.is_a?(Business)
        UrlHelpers.stafftools_enterprise_path(owner)
      else
        UrlHelpers.stafftools_user_path(owner)
      end
    end
  end
end
