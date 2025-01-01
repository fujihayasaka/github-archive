# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class DeleteStripeComponent < ApplicationComponent
      DOWNLOAD_STRIPE_DATA_DOCS_URL = "https://github.com/github/sponsors/blob/main/stripe/" \
        "deleting-stripe-accounts.md#deleting-a-stripe-account-that-had-prior-activity"

      def initialize(sponsorable:, stripe_account:)
        @sponsorable = sponsorable
        @stripe_account = stripe_account
      end

      sig { returns T::Boolean }
      memoize def render?
        sponsorable.present? && stripe_account.present?
      end

      sig { returns String }
      def menu_item_label
        "Delete"
      end

      sig { returns String }
      memoize def modal_id
        "delete-stripe-modal-#{stripe_account&.stripe_account_id}"
      end

      private

      attr_reader :sponsorable, :stripe_account

      delegate :sponsors_listing, to: :stripe_account, allow_nil: true

      memoize def human_reason_delete_is_not_allowed
        return if allow_delete?
        case stripe_account.reason_delete_is_not_allowed
        when :active_account
          "You can't delete @#{sponsorable}'s only active Stripe Connect account."
        when :positive_balance
          "You cannot delete a Stripe Connect account that has a positive balance."
        end
      end

      memoize def allow_delete?
        stripe_account.deletable_by?(current_user)
      end

      def show_prior_activity_warning?
        stripe_account.had_prior_activity?
      end
    end
  end
end
