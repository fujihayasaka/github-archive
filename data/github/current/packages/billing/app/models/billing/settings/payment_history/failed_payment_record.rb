# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module PaymentHistory
      class FailedPaymentRecord < PaymentRecord
        def url_for_receipt
          nil
        end

        def status_icon
          "x"
        end

        def status
          "failed"
        end

        def status_level
          :danger
        end
      end
    end
  end
end
