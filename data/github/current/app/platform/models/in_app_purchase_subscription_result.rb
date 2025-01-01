# typed: strict
# frozen_string_literal: true

# Basic modeling for describing the result of a subscription creation attempt for a singular product.
module Platform
  module Models
    class InAppPurchaseSubscriptionResult < T::Struct

      const :success, T::Boolean

      const :message, String

      sig { returns(InAppPurchaseSubscriptionResult) }
      def self.success
        new(success: true, message: "")
      end

      sig { params(message: String).returns(InAppPurchaseSubscriptionResult) }
      def self.failure(message:)
        new(success: false, message:)
      end
    end
  end
end
