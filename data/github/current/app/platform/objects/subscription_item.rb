# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class SubscriptionItem < Platform::Objects::Base

      model_name "Billing::SubscriptionItem"
      description "An account's subscription item, representing something they pay for"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: ::Platform::Authorization::Permission, object: T.untyped).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: ::Platform::Authorization::Permission, object: T.untyped).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, object)
        object.async_subscribable.then do |subscribable|
          subscribable.async_listing.then do |listing|
            if listing
              listing.async_owner.then do
                if permission.current_integratable_owner.present?
                  object.async_viewable_by?(permission.current_integratable_owner).then do |viewable|
                    if viewable
                      true
                    else
                      permission.viewer.present? && object.async_viewable_by?(permission.viewer)
                    end
                  end
                else
                  permission.viewer.present? && object.async_viewable_by?(permission.viewer)
                end
              end
            else
              permission.viewer.present? && object.async_viewable_by?(permission.viewer)
            end
          end
        end
      end

      visibility :internal
      minimum_accepted_scopes ["user"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the SubscriptionItem object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field(visibility: :internal)

      field :created_at, Scalars::DateTime, "Identifies the date and time when the subscription item was first created.", null: true

      field :updated_at, Scalars::DateTime, "Identifies the date and time when the subscription item was last updated.", null: true

      field :has_pending_cycle_change, Boolean, description: "Returns whether the subscription item has a pending plan change", null: false,
        method: :async_has_pending_cycle_change?

      field :pending_change_id, Integer, description: "Returns the id of a pending plan change", null: true
      sig { returns(Promise[T.nilable(Integer)]) }
      def pending_change_id
        object.async_pending_change_id
      end

      field :marketplace_pending_change, PendingMarketplaceChange, description: "Pending change related to this item",
        null: true, method: :async_pending_subscription_item_change

      field :subscribable_pending_change, PendingSubscribableChange, description: "Pending change related to this item", null: true,
        method: :async_pending_subscription_item_change

      field :quantity, Integer, "The number of units for this item.", null: false

      field :paid, Boolean, description: "Returns true if the subscription item is not free or on free trial", null: false
      sig { returns(Promise[T::Boolean]) }
      def paid
        object.async_listing_plan.then { object.paid? }
      end

      field :on_free_trial, Boolean, description: "Is the subscription item currently on free trial", null: false, method: :on_free_trial?

      field :free_trial_ends_on, Scalars::DateTime, description: "Date the free trial ends", null: true
      sig { returns(T.nilable(DateTime)) }
      def free_trial_ends_on
        object.free_trial_ends_on.try(:to_datetime)
      end

      field :billing_cycle, String, description: "The billing cycle for the plan associated with this item", null: false
      sig { returns(Promise[String]) }
      def billing_cycle
        object.async_plan_subscription.then do |plan_subscription|
          plan_subscription.async_user.then do
            plan_subscription.plan_duration # delegated through the user
          end
        end
      end

      field :next_billing_date, Scalars::DateTime, description: "The next billing date for the plan associated with this item", null: true
      sig { returns(Promise[T.nilable(DateTime)]) }
      def next_billing_date
        object.async_plan_subscription.then do |plan_subscription|
          plan_subscription.async_user.then do |user|
            user.try(:next_billing_date).try(:to_datetime) # delegated through the user
          end
        end
      end

      field :account_has_been_charged, Boolean, description: "Whether an account has been charged for this subscription, during signup or at the end of a free trial", null: false
      sig { returns(Promise[T::Boolean]) }
      def account_has_been_charged
        object.async_subscribable.then do |_subscribable|
          object.account_has_been_charged?
        end
      end

      # N.B Need to figure out what a Currency Scalar looks like
      field :price, Scalars::Money, description: "The total price for the item.", null: false do
        argument :free_trial, Boolean, "Should the price check for an eligible free trial?", default_value: true, required: false
        argument :duration, Platform::Enums::Billing::Duration, "The duration for which the price should be computed. Defaults to the current plan duration.", required: false
      end
      sig { params(arguments: T.untyped).returns(Promise[Billing::Money]) }
      def price(**arguments)
        object.async_price(trial_price: arguments[:free_trial], duration: arguments[:duration])
      end

      field :post_trial_prorated_price, Scalars::Money, description: "The price for this item after the free trial ends.", null: true,
      method: :async_post_trial_prorated_price

      field :post_trial_bill_date, Scalars::DateTime, description: "The next_billing_date after the free trial ends.", null: false
      sig { returns(Promise[DateTime]) }
      def post_trial_bill_date
        pricing_promise do |user|
          post_trial_bill_date = user.subscription.next_bill_date_after \
            date: user.subscription.free_trial_end_date
        end
      end

      # Load some pricing-related values,
      # then yield to the block.
      # This is useful for fields that need pricing info.
      sig { params(block: T.proc.params(arg0: ::User).void).returns(Promise[T.untyped]) }
      def pricing_promise(&block)
        object.async_account.then do |user|
          relations = [
            user.async_coupons,
            user.async_asset_status,
            user.async_pending_cycle_change,
            user.async_pending_subscription_item_changes,
            user.async_plan_subscription,
          ]

          Promise.all(relations).then do |_, _, _, _, plan_subscription|
            if plan_subscription
              # Pricing interfaces are still subscription-based, but billing is customer-based.
              # We need to resolve the plan subscription back to the customer to ensure we're capturing
              # subsciption items from all of a customer's subscriptions.
              plan_subscription.async_customer.then do |customer|
                # guard missing customer (see https://github.com/github/github/pull/260158#issuecomment-1443873464)
                items_plans_promise = if customer
                  customer.async_subscription_items.then do |items|
                    subscribable_promises = items.map(&:async_subscribable)
                    Promise.all(subscribable_promises + [customer.async_active_subscription_items])
                  end
                else
                  Promise.resolve([])
                end
                items_plans_promise.then { yield(user) }
              end
            else
              yield(user)
            end
          end
        end
      end

      field :authorization_required, Boolean, description: "Has the purchased product been authorized for the account?", null: false
      sig { returns(Promise[T::Boolean]) }
      def authorization_required
        object.async_authorization_required?(context[:viewer])
      end

      field :is_installed, Boolean, description: "Whether the item has been installed. Only relevant for GitHub or OAuth apps purchases.", null: false
      sig { returns(T::Boolean) }
      def is_installed
        object.installed_at.present?
      end

      field :subscribable, Unions::BillingSubscribable, description: "The object that this is a subscription to.", null: false

      field :marketplace_listing, MarketplaceListing, method: :async_listing, description: "The marketplace listing that this is a purchase of", null: true

      field :account, Platform::Unions::Account, visibility: :internal, description: "The account associated with this subscription item", null: true
      sig { returns(Promise[T.nilable(::User)]) }
      def account
        object.async_plan_subscription.then do |plan_subscription|
          if plan_subscription.async_user.value.nil?
            Platform::Loaders::ActiveRecord.load(::Organization, plan_subscription.org_id_by_sub_item_id[object.id])
          else
            plan_subscription.async_user
          end
        end
      end

      field :formatted_total_price, String, description: "The total price for this subscription item, based on the owner's plan duration, formatted as a money string.", null: false, method: :async_formatted_total_price

      field :prorated_total_price_in_cents, Integer, description: "The total price for this subscription item, prorated to end of the owner's current billing cycle, in cents.", null: false
      sig { returns(Promise[Integer]) }
      def prorated_total_price_in_cents
        object.async_subscribable.then do |subscribable|
          object.async_account.then do |owner|
            owner.async_plan_subscriptions.then do
              subscribable.prorated_total_price(account: owner, quantity: object.quantity).cents
            end
          end
        end
      end

      field :formatted_prorated_total_price, String, description: "The total price for this subscription item, prorated to end of the owner's current billing cycle, formatted as a money string.", null: false
      sig { returns(Promise[String]) }
      def formatted_prorated_total_price
        object.async_subscribable.then do |subscribable|
          object.async_account.then do |owner|
            owner.async_plan_subscriptions.then do
              subscribable.prorated_total_price(account: owner, quantity: object.quantity).format
            end
          end
        end
      end

      field :viewer_can_admin, Boolean, description: "Can the current user cancel or edit this subscription item.", null: false
      sig { returns(Promise[T::Boolean]) }
      def viewer_can_admin
        object.async_adminable_by?(context[:viewer])
      end
    end
  end
end
