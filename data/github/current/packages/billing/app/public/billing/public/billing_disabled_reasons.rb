# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    class BillingDisabledReasons < T::Enum
      enums do
        AuthorizationFailure = new(:authorization_failure)
        BlocklistedPaymentMethod = new(:blocklisted_payment_method)
      end
    end
  end
end
