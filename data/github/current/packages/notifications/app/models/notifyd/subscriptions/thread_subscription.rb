# typed: strict
# frozen_string_literal: true

module Notifyd
  module Subscriptions
    class ThreadSubscription < T::Struct
      const :subscribed, T::Boolean
      const :created_at, T.nilable(Integer)
    end
  end
end
