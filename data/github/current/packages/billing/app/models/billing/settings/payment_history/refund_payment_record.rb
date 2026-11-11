# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module PaymentHistory
      class RefundPaymentRecord < PaymentRecord
        def status_icon
          "reply"
        end

        def status_level
          :attention
        end

        def status
          "refund"
        end

        def refund_amount
          Billing::Money.new(refund_amount_in_cents).format
        end
      end
    end
  end
end
