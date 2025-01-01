# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class CreateManualPayoutComponent < ApplicationComponent
      def initialize(stripe_account:)
        @stripe_account = stripe_account
      end

      sig { returns T::Boolean }
      memoize def render?
        return false unless stripe_account.present?
        return false unless sponsors_listing.present?
        return false unless active_stripe_account.present?

        active_stripe_account.balance_amount.cents > 0
      end

      sig { returns String }
      def menu_item_label
        "Issue manual payout"
      end

      sig { returns String }
      memoize def modal_id
        "create-manual-payout-modal-#{stripe_account&.stripe_account_id}"
      end

      private

      attr_reader :stripe_account

      delegate :sponsorable, to: :sponsors_listing, allow_nil: true
      delegate :sponsors_listing, to: :stripe_account, allow_nil: true

      def manual_payout_restricted?
        sponsorable.has_commercial_interaction_restriction?
      end

      memoize def active_stripe_account
        sponsors_listing.active_stripe_account_for_self_or_fiscal_host
      end
    end
  end
end
