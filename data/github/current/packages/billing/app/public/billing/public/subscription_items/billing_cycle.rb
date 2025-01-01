# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    module SubscriptionItems
      class BillingCycle < T::Enum
        enums do
          Month = new
          Year = new
        end
      end
    end
  end
end
