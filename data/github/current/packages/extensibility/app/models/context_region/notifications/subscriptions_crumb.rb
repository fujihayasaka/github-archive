# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Notifications
    class SubscriptionsCrumb < Crumb
      sig { override.returns(String) }
      def label
        "Subscriptions"
      end

      sig { override.returns(Crumb) }
      def parent
        NotificationsCrumb.new
      end
    end
  end
end
