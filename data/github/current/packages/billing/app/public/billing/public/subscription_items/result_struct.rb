# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    module SubscriptionItems
      class ResultStruct < T::Struct
        const :subscription_item, T.nilable(Billing::SubscriptionItem)
        const :change_scheduled, T::Boolean, default: false
        const :result, Billing::Public::ResultStruct
        # The Zuora payment id for the advance payment collected during an upgrade, if any.
        const :payment_id, T.nilable(String), default: nil
      end
    end
  end
end
