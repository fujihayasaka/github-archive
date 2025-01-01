# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class PlanChange < Platform::Objects::Base
      description "A plan change for a given subscription that provides pricing details"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(permission: Platform::Authorization::Permission, _object: T.untyped)
          .returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(permission: Platform::Authorization::Permission, object: T.untyped)
          .returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      scopeless_tokens_as_minimum

      field :final_price, Scalars::Money, description: "prorated final price to apply the plan change", null: false do
        T.bind(self, Platform::Objects::Base::Field)

        argument :github_only, Boolean, "Should the final price only include GitHub items?", required: false, default_value: false
        argument :use_balance, Boolean, "Should the final price include the account balance?", required: false, default_value: false
      end
      sig { params(github_only: T::Boolean, use_balance: T::Boolean).returns(Money) }
      def final_price(github_only: false, use_balance: false)
        object.final_price github_only: github_only, use_balance: use_balance
      end

      field :subscription_item, Objects::SubscriptionItem, description: "the subscription item tied to a plan change for a given listing plan", null: false do
        T.bind(self, Platform::Objects::Base::Field)

        argument :subscribable_id, ID, "The ID for the listing plan or sponsors tier tied to the item", required: false
        argument :quantity, Integer, "An optional quantity to override the planChange amount.", required: false
      end

      sig do
        params(subscribable_id: T.nilable(T.any(String, Integer)), quantity: T.nilable(Integer))
          .returns(Promise[T.nilable(Billing::SubscriptionItem)])
      end
      def subscription_item(subscribable_id: nil, quantity: nil)
        Platform::Helpers::NodeIdentification.async_typed_object_from_id(
          Objects::Subscription::SUBSCRIBABLE_TYPES, subscribable_id, context
        ).then do |subscribable|
          object.subscription_item(subscribable: subscribable, quantity: quantity)
        end
      end
    end
  end
end
