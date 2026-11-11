# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingCycle < Platform::Objects::Base
      description "Represents the pending cycle for an account."

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

      field :data_packs, Integer, "The number of LFS packs.", null: true
      field :payment_amount, Scalars::Money, "The total cost of the next billing cycle.", null: false,
        method: :async_payment_amount
      field :plan, Objects::Plan, "The type of plan.", null: false
      field :plan_duration, Enums::Billing::Duration, "The duration of the plan.", null: false
      field :seats, Integer, "The number of seats.", null: true

      field :active_on, Scalars::DateTime, description: "When this pending cycle will be active, and any pending changes will be applied to the account's subscription.", null: true

      def active_on
        return @object.active_on if @object.pending_cycle_change
        @object.account.business&.async_customer.then do
          @object.active_on
        end
      end

      field :has_changes, Boolean, description: "Are there any pending changes being applied to the next billing cycle?", null: false

      def has_changes
        if @object.pending_cycle_change
          @object.pending_cycle_change.async_user.then do
            @object.has_changes?(including_free_trials: false)
          end
        else
          @object.has_changes?(including_free_trials: false)
        end
      end

      field :data_packs_price, Scalars::Money, method: :discounted_data_packs_price, description: "The total cost of data packs with discounts applied.", null: false

      field :plan_price, Scalars::Money, method: :discounted_plan_price, description: "The total cost of the GitHub plan with discounts applied.", null: false

      field :is_downgrading, Boolean, description: "Does the pending cycle have any downgrades being applied?", null: false, method: :downgrading?

      field :is_changing_duration, Boolean, description: "Does the pending cycle have a change to the plan duration?", null: false

      def is_changing_duration
        !!@object.changing_duration?
      end

      field :is_changing_data_packs, Boolean, description: "Does the pending cycle have a change to the data packs?", null: false

      def is_changing_data_packs
        !!@object.changing_data_packs?
      end

      field :is_changing_seats, Boolean, description: "Does this pending cycle have any changes to its seat count or include a plan with seats?", null: false

      def is_changing_seats
        @object.plan.per_seat? && @object.seats && @object.seats > 0
      end

      field :pending_marketplace_changes, resolver: Resolvers::PendingMarketplaceChanges,
        description: "Changes to sponsorships or Marketplace purchases associated with the next billing cycle.",
        null: false, connection: true
      field :pending_subscribable_changes, resolver: Resolvers::PendingSubscribableChanges,
        description: "Changes to subscribable purchases associated with the next billing cycle.", null: false,
        connection: true
    end
  end
end
