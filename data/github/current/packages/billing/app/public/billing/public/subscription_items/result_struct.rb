# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    module SubscriptionItems
      class ResultStruct < T::Struct
        const :subscription_item, T.nilable(Billing::SubscriptionItem)
        const :change_scheduled, T::Boolean, default: false
        const :result, Billing::Public::ResultStruct
      end
    end
  end
end
