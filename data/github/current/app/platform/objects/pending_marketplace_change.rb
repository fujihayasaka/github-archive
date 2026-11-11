# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingMarketplaceChange < Platform::Objects::Base
      model_name "Billing::PendingSubscriptionItemChange"
      description "Represents a pending change for a sponsorship or Marketplace purchase."

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

      field :id, Integer, "The database id for the pending marketplace change.", null: false
      field :is_cancellation, Boolean, "Is the pending change a cancellation?", method: :cancellation?, null: false
      field :quantity, Integer, "The number of units for the marketplace purchase.", null: true

      # nb: when this object is made public, consider naming this field `effective_date` to match the REST API
      field :active_on, Scalars::DateTime, "When the change is effective", null: false

      field :can_apply, Boolean, description: "Can this change be applied immediately?", null: false

      def can_apply
        @object.async_listing.then(&:draft?)
      end

      field :subscribable, Objects::MarketplaceListingPlan, method: :async_subscribable,
        description: "The subscribable object that this change is related to.", null: false

      field :price, Scalars::Money, description:
        "The total cost of the sponsorship or Marketplace purchase for the next billing cycle.", null: false

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
              # Pricing interfaces are still subscription-based, but billing is customer-based.
              # We need to resolve the plan subscription back to the customer to ensure we're capturing
              # subsciption items from all of a customer's subscriptions.
              plan_subscription.async_customer.then do |customer|
                # guard missing customer (see https://github.com/github/github/pull/260158#issuecomment-1443873464)
                if customer
                  customer.async_active_subscription_items.then do
                    @object.price
                  end
                else
                  @object.price
                end
              end
            end
          end
        end
      end
    end
  end
end
