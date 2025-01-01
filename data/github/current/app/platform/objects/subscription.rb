# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class Subscription < Platform::Objects::Base
      extend T::Sig

      model_name "Billing::PlanSubscription"
      description "The billing subscription for an account."

      SUBSCRIBABLE_TYPES = T.let([Objects::MarketplaceListingPlan, Objects::SponsorsTier], T::Array[T.untyped])


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
      # TODO: before going public, add more logic here
      sig { params(permission: ::Platform::Authorization::Permission, object: T.untyped).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      scopeless_tokens_as_minimum

      # Load some pricing-related values,
      # then yield to the block.
      # This is useful for fields that need pricing info.
      sig { params(blk: T.proc.params(user: ::User).void).returns(Promise[T.untyped]) }
      def pricing_promise(&blk)
        object.async_user.then do |user|
          relations = [
            user.async_coupons,
            user.async_asset_status,
            user.async_pending_cycle_change,
            user.async_pending_subscription_item_changes,
            user.async_plan_subscription,
            user.async_customers,
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
      # TODO For a later time...
      # Move plan and seat into SubscriptionItem? That way plan and seat are now
      # both *line* items.
      field :plan, Objects::Plan, description: "The billing plan for the billing subscription.", null: false
      sig { returns(Promise[GitHub::Plan]) }
      def plan
        object.async_user.then do |_user|
          # NB we delegate plan off of user on the PlanSubscription model.
          # We should finally get to moving this off the user and
          # onto the plan object.
          object.plan
        end
      end

      field :seats, Integer, description: "The quantity of seats purchased with this billing subscription.", null: false
      sig { returns(Promise[Integer]) }
      def seats
        object.async_user.then do |_user|
          object.seats
        end
      end

      field :start_date, Scalars::DateTime, description: "The date the billing subscription cycle starts.", null: false
      sig { returns(Promise[Time]) }
      def start_date
        pricing_promise do |user|
          user.subscription.service_starts_on.to_time :utc
        end
      end

      field :end_date, Scalars::DateTime, description: "The date the billing subscription cycle ends.", null: false
      sig { returns(Promise[Time]) }
      def end_date
        pricing_promise do |user|
          user.subscription.service_ends_on.to_time :utc
        end
      end

      # N.B We provide a 'helper' on `BillingDependency` to calculate the
      # `next_billing_date`, but also have a delegate to BT sub to grab it.
      field :next_billing_date, Scalars::DateTime, description: "The date the billing subscription cycle will next bill.", null: false
      sig { returns(Promise[Time]) }
      def next_billing_date
        object.async_user.then do |user|
          if user.delegate_billing_to_business?
            user.business.async_customer.then do
              user.next_billing_date.to_time :utc
            end
          else
            user.next_billing_date.to_time :utc
          end
        end
      end

      field :duration, Enums::Billing::Duration, description: "The billing cycle to charge the billing subscription.",
        null: false, method: :async_plan_duration

      field :discounted_price, Float, description: "The total price after discounts for the billing subscription.", null: false do
        argument :use_balance, Boolean, "include the billing subscription balance for the price.", required: false
        argument :prorate, Boolean, "prorate the discountedPrice for the amount of service remaining.", required: false
      end
      sig { params(use_balance: T.nilable(T::Boolean), prorate: T.nilable(T::Boolean)).returns(Promise[Float]) }
      def discounted_price(use_balance: nil, prorate: nil)
        pricing_promise do |user|
          user.pending_cycle.payment_amount(use_balance: use_balance, prorate: prorate)
        end
      end

      field :undiscounted_price, Float, description: "The total price before discounts for the billing subscription.", null: false
      sig { returns(Promise[Float]) }
      def undiscounted_price
        pricing_promise do |user|
          user.subscription.undiscounted_price
        end
      end

      field :discount, Float, description: "The discount amount applied for the billing subscription.", null: false
      sig { returns(Promise[Float]) }
      def discount
        pricing_promise do |user|
          user.subscription.discount
        end
      end

      field :balance, Float, description: "The balance on the billing subscription.", null: false
      sig { returns(Promise[Float]) }
      def balance
        # N.B should refactor this since this actually sits on the
        # user. Or possibly just access this right off the user and do
        # the proper coercion into a Billing::Money object.
        #
        # Currently, balance is passed into the Billing::Subscription which
        # shoves it into price as cents so it can be wrapped into a Billing::Money.
        pricing_promise do |user|
          user.subscription.balance
        end
      end

      field :free_trial_end_date, Scalars::DateTime, description: "The date a free trial on this subscription would end.", null: false
      sig { returns(Promise[Time]) }
      def free_trial_end_date
        pricing_promise do |user|
          user.subscription.free_trial_end_date.to_time :utc
        end
      end

      field :post_free_trial_bill_date, Scalars::DateTime, description: "The next_billing_date after the free trial ends.", null: false
      sig { returns(Promise[Time]) }
      def post_free_trial_bill_date
        pricing_promise do |user|
          post_trial_bill_date = user.subscription.next_bill_date_after \
            date: user.subscription.free_trial_end_date
          post_trial_bill_date.to_time :utc
        end
      end

      field :post_trial_prorated_total_price, Scalars::Money, description: "the prorated amount the user will pay for the remainder of the subscription after the free trial ends", null: false do
        argument :id, ID, "the ID of a MarketplaceListingPlan", required: false
        argument :quantity, Integer, "number of units of this plan that would be purchased", required: false
      end
      sig { params(id: T.nilable(Integer), quantity: T.nilable(Integer)).returns(Promise[Billing::Money]) }
      def post_trial_prorated_total_price(id: nil, quantity: nil)
        pricing_promise do |user|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id([Platform::Objects::MarketplaceListingPlan], id, context).then do |listing_plan|
            object.async_post_trial_prorated_total_price(listing_plan: listing_plan, user: user, quantity: quantity)
          end
        end
      end

      field :subscription_item, Objects::SubscriptionItem, description: "Returns a subscription item for a given Marketplace or Sponsors listing slug.", null: true do
        argument :listing_slug, String, "The slug of the Marketplace or Sponsors listing.", required: true
        argument :active, Boolean, "Filter out cancelled subscription items if set to true.", required: false
      end
      sig { params(listing_slug: String, active: T.nilable(T::Boolean)).returns(Promise[Billing::SubscriptionItem]) }
      def subscription_item(listing_slug:, active: nil)
        pricing_promise do |user|
          user.async_plan_subscription.then do |plan_subscription|
            if plan_subscription
              plan_subscription.async_subscription_items.then do |items|
                items.select! { |item| item.active? } if active

                item_match_promises = items.map do |item|
                  item.async_subscribable.then do |subscribable|
                    next unless subscribable
                    subscribable.async_listing.then do |listing|
                      listing && listing.slug == listing_slug
                    end
                  end
                end

                Promise.all(item_match_promises).then do |results|
                  match_idx = results.find_index(true)
                  match_idx && items[match_idx]
                end
              end
            else
              nil
            end
          end
        end
      end

      field :pending_cycle, Objects::PendingCycle, description: "Returns the pending cycle for a given subscription.", null: true
      sig { returns(Promise[T.nilable(Billing::PendingCycle)]) }
      def pending_cycle
        object.async_user.then do |user|
          relations = [
            user.async_pending_subscription_item_changes,
            object.async_subscription_items,
            user.async_plan_subscription,
            user.async_asset_status,
          ]

          Promise.all(relations).then do |psi_changes, subscription_items, plan_subscription, _|
            promises = subscription_items.map(&:async_subscribable)
            if plan_subscription
              load_items_promise = plan_subscription.async_subscription_items.then do |items|
                items.map(&:async_subscribable)
              end

              promises << load_items_promise
            end

            psi_promises = psi_changes.to_a.map do |item|
              item_rel = [
                item.async_subscribable,
                item.async_pending_plan_change,
              ]
              Promise.all(item_rel).then do |_, plan_change|
                plan_change.async_user.then do |change_user|
                  change_user.async_asset_status.then do
                    change_user.async_plan_subscription.then do |change_user_plan_subscription|
                      if change_user_plan_subscription
                        change_user_plan_subscription.async_subscription_items
                      end
                    end
                  end
                end
              end
            end

            promises.concat(psi_promises)
            Promise.all(promises).then { user.pending_cycle }
          end
        end
      end

      field :plan_change, Objects::PlanChange, description: "Returns a plan change object for a set of changes.", null: true do
        argument :plan, String, "The new GitHub plan", required: false
        argument :seats, Integer, "The new seat count", required: false
        argument :asset_packs, Integer, "The new asset pack count", required: false
        argument :billing_duration, Enums::Billing::Duration, "The new billing duration", required: false
        argument :subscribable_id, ID, "The id of a new marketplace plan or sponsors tier", required: false
        argument :subscribable_quantity, Integer, "The quantity for the new marketplace plan or sponsors tier", required: false
      end
      sig do
        params(
          plan: T.nilable(String),
          seats: T.nilable(Integer),
          asset_packs: T.nilable(Integer),
          billing_duration: T.nilable(String),
          subscribable_id: T.nilable(T.any(Integer, String)),
          subscribable_quantity: T.nilable(Integer),
        ).returns(Promise[T.nilable(Billing::PlanChange)])
      end
      def plan_change(plan: nil, seats: nil, asset_packs: nil, billing_duration: nil, subscribable_id: nil, subscribable_quantity: nil)
        pricing_promise do |user|
          subscribable_promise = if subscribable_id
            Platform::Helpers::NodeIdentification.async_typed_object_from_id(SUBSCRIBABLE_TYPES, subscribable_id, context)
          else
            Promise.resolve(nil)
          end

          subscribable_promise.then do |subscribable|
            object.async_plan_change(
              billable_entity: user,
              plan: plan,
              seats: seats,
              asset_packs: asset_packs,
              billing_duration: billing_duration,
              subscribable: subscribable,
              subscribable_quantity: subscribable_quantity,
            )
          end
        end
      end

      field :eligible_for_free_trial_on_listing, Boolean, description: "Returns eligibility for free trials for a listing", null: false do
        argument :listing_slug, String, "Listing slug for listing to check eligibility", required: true
      end
      sig { params(listing_slug: String).returns(Promise[T::Boolean]) }
      def eligible_for_free_trial_on_listing(listing_slug:)
        Loaders::ActiveRecord.load(::Marketplace::Listing, listing_slug, column: :slug).then do |listing|
          object.eligible_for_free_trial_on_listing?(listing)
        end
      end

      field :subscription_items, Connections::SubscriptionItem, description: "Additional add ons associated with the billing subscription.", null: false, connection: true do
        argument :active, Boolean, "Filter out cancelled subscription items.", required: false
        argument :subscribable_type, Enums::SubscriptionItemSubscribableType,
          "Filter to just the subscription items of the given type.", required: false
      end
      sig { params(active: T.nilable(T::Boolean), subscribable_type: T.nilable(String)).returns(T::Enumerable[Billing::SubscriptionItem]) }
      def subscription_items(active: nil, subscribable_type: nil)
        items = object.subscription_items.scoped
        items = items.where(subscribable_type: subscribable_type) if subscribable_type
        items = items.active if active
        items
      end

      field :on_free_trial, Boolean, description: "Returns whether or not the plan subscription is a free trial", null: false
      sig { returns(Promise[T::Boolean]) }
      def on_free_trial
        pricing_promise do |user|
          user.plan_trial_active?(nil)
        end
      end
    end
  end
end
