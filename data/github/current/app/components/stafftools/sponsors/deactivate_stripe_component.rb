# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class DeactivateStripeComponent < ApplicationComponent
      def initialize(stripe_account:)
        @stripe_account = stripe_account
      end

      sig { returns T::Boolean }
      memoize def render?
        stripe_account.present?
      end

      sig { returns String }
      memoize def modal_id
        "deactivate-stripe-modal-#{stripe_account&.stripe_account_id}"
      end

      sig { returns String }
      def menu_item_label
        "Deactivate"
      end

      private

      attr_reader :stripe_account

      delegate :stripe_account_id, :stripe_dashboard_url, :sponsors_listing, to: :stripe_account
      delegate :sponsorable, to: :sponsors_listing

      memoize def reason_deactivate_is_not_allowed
        if stripe_account.active? && sponsors_listing.approved?
          "Can't deactivate the only active Stripe account for a published Sponsors profile"
        elsif has_balance_in_stripe?
          "Account currently has a positive balance"
        elsif any_ledger_entries?
          "Can't deactivate an account that has had money, including #{ledger_entry_summary}"
        end
      end

      def allow_deactivate?
        reason_deactivate_is_not_allowed.blank?
      end

      def any_ledger_entries?
        ledger_entry_counts.any? { |_transaction_type, count| count > 0 }
      end

      def ledger_entry_summary
        entry_descriptions = ledger_entry_counts.map do |transaction_type, count|
          article_or_count = count == 1 ? article_for(transaction_type) : count
          "#{article_or_count} #{human_transaction_type(transaction_type).pluralize(count)}"
        end
        entry_descriptions.to_sentence
      end

      def human_transaction_type(transaction_type)
        return "GitHub match" if transaction_type == "github_match"
        return "GitHub match reversal" if transaction_type == "github_match_reversal"
        transaction_type.humanize.downcase
      end

      def article_for(transaction_type)
        return "an" if transaction_type == "invoice_credit"
        "a"
      end

      memoize def ledger_entry_counts
        stripe_account.ledger_entries.group(:transaction_type).count
      end

      memoize def has_balance_in_stripe?
        sponsors_listing.has_balance_in_stripe?(stripe_account)
      end
    end
  end
end
