# typed: strict
# frozen_string_literal: true

module Billing
  module Public

    # When creating a new subscription item via Billing::CreateSubscriptionItem we need to pass the necessary in-app purchase information,
    # so that we can create the appropriate AppleSubscription or GoogleSubscription records. As a rule of thumb a SubscriptionItem can have
    # either an AppleSubscription or a GoogleSubscription, but not both. Since both subscription types will have a single identifier, which is
    # either an original transaction id for Apple or a purchase token for Google, this struct allows us to pass a single generic in-app purchase object to
    # CreateSubscriptionItem. We can then use the identifier and type to create the appropriate subscription record and also check if the existing
    # in-app purchase record of a subscription item belongs to Apple or Google.
    class InAppPurchase < T::Struct
      extend T::Sig

      class Type < T::Enum
        enums do
          Apple = new
          Google = new
        end
      end

      const :identifier, String
      const :type, Type

      sig { params(original_transaction_id: String).returns(InAppPurchase) }
      def self.apple(original_transaction_id:)
        new(identifier: original_transaction_id, type: Type::Apple)
      end

      sig { params(purchase_token: String).returns(InAppPurchase) }
      def self.google(purchase_token:)
        new(identifier: purchase_token, type: Type::Google)
      end

      sig { params(other: InAppPurchase).returns(T::Boolean) }
      def ==(other)
        identifier.to_s.downcase == other.identifier.to_s.downcase && type == other.type
      end
      alias eql? ==
    end
  end
end
