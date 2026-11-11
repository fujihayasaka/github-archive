# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingSubscribableChange < Platform::Objects::Base
      model_name "Billing::PendingSubscriptionItemChange"
      description "Represents a pending change for a subscribable purchase."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      scopeless_tokens_as_minimum

      field :id, Integer, "The database id for the pending subscribable change.", null: false
      field :is_cancellation, Boolean, "Is the pending change a cancellation?", method: :cancellation?, null: false
      field :quantity, Integer, "The number of units for the subscribable purchase.", null: true

      # nb: when this object is made public, consider naming this field `effective_date` to match the REST API
      field :active_on, Scalars::DateTime, "When the change is effective", null: false

      field :can_apply, Boolean, description: "Can this change be applied immediately?", null: false,
        method: :async_can_apply?

      field :subscribable, Unions::BillingSubscribable, method: :async_subscribable, description: "The subscribable object, such as a Marketplace listing plan or GitHub Sponsors tier, that this change is related to.", null: false

      field :price, Scalars::Money, description: "The total cost of the subscribable purchase for the next billing cycle.", null: false

      def price
        Promise.all(
          [
            @object.async_subscribable,
            @object.async_pending_plan_change,
          ],
        ).then do |_, pending_change|
          pending_change.async_user.then do |user|
            Promise.all([
              user.async_asset_status,
              user.async_plan_subscription,
            ]).then do |_, plan_subscription|
              plan_subscription.async_subscription_items.then do
                @object.price
              end
            end
          end
        end
      end
    end
  end
end
