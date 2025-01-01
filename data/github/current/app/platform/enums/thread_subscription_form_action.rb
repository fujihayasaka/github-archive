# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ThreadSubscriptionFormAction < Platform::Enums::Base
      description "The possible states of a thread subscription form action"

      value "NONE", "The User cannot subscribe or unsubscribe to the thread", value: :none
      value "SUBSCRIBE", "The User can subscribe to the thread", value: :subscribe
      value "UNSUBSCRIBE", "The User can unsubscribe to the thread", value: :unsubscribe

    end
  end
end
