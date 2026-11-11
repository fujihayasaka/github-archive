# typed: true
# frozen_string_literal: true

module Billing
  class Dispute < ApplicationRecord::Domain::Billing # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
    self.table_name = "billing_disputes"

    belongs_to :user
    belongs_to :billing_transaction, class_name: "Billing::BillingTransaction"

    enum :platform, {
      unknown: 0,
      stripe: 1,
    }

    delegate :transaction_id, to: :billing_transaction

    delegate :url,
      :response_url,
      to: :platform_dispute, allow_nil: true

    # Public: Money amount of this dispute
    #
    # Returns Money
    def amount
      Billing::Money.new(amount_in_subunits, currency_code)
    end

    private

    def platform_dispute
      return @platform_dispute if defined?(@platform_dispute)

      @platform_dispute =
        case platform.to_sym
        when :stripe
          ::Billing::Dispute::StripeDispute.new(self)
        end
    end
  end
end
