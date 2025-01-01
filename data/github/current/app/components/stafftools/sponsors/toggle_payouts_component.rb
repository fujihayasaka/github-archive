# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class TogglePayoutsComponent < ApplicationComponent
      def initialize(stripe_account:)
        @stripe_account = stripe_account
      end

      sig { returns T::Boolean }
      memoize def render?
        stripe_account.present?
      end

      sig { returns String }
      memoize def menu_item_label
        if payouts_disabled?
          "Enable payouts"
        else
          "Disable payouts"
        end
      end

      sig { returns String }
      memoize def modal_id
        "toggle-payouts-modal-#{stripe_account&.stripe_account_id}"
      end

      private

      attr_reader :stripe_account

      delegate :sponsors_listing, to: :stripe_account, allow_nil: true

      memoize def sponsorable
        sponsors_listing.sponsorable
      end

      memoize def payouts_disabled?
        stripe_account.automated_payouts_disabled?
      end

      def account_verified?
        stripe_account.verified_verification_status?
      end

      def payouts_restricted?
        sponsorable.has_commercial_interaction_restriction?
      end

      def unsupported_monthly_payouts?
        !stripe_account.billing_country_supports_monthly_payouts?
      end

      def allow_enabled?
        payouts_disabled? && reason_enabled_is_not_allowed.blank?
      end

      def reason_enabled_is_not_allowed
        if !account_verified?
          "Stripe account is unverified"
        elsif payouts_restricted?
          "Payouts restricted due to commercial interaction restrictions"
        elsif unsupported_monthly_payouts?
          "The payout interval 'monthly' is not available for merchants in #{stripe_account.billing_country_name}"
        end
      end

      def body
        if payouts_disabled?
          "Enable automatic Stripe payouts for this account."
        else
          "Disable automatic Stripe payouts for this account."
        end
      end

      def form_method
        payouts_disabled? ? :post : :delete
      end

      def button_class
        "menu-item-danger" unless payouts_disabled?
      end
    end
  end
end
