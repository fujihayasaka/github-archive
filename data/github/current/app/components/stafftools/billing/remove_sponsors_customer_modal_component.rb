# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class RemoveSponsorsCustomerModalComponent < ApplicationComponent
      extend T::Sig

      sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
      def initialize(sponsor:)
        @sponsor = sponsor
        @sponsors_customer = T.let(sponsor.sponsors_customer, T.nilable(Customer))
      end

      sig { returns T::Boolean }
      def render?
        return false unless @sponsors_customer
        !!(GitHub.sponsors_enabled? && @sponsors_customer.sponsors_purpose?)
      end

      private

      sig { returns GitHubSponsors::Types::Sponsor }
      attr_reader :sponsor

      sig { returns Customer }
      def sponsors_customer
        T.must_because(@sponsors_customer) { "#render? ensures non-nil" }
      end

      sig { returns T::Boolean }
      def disabled?
        disabled_reason.present?
      end

      sig { returns T.nilable(String) }
      memoize def disabled_reason
        total_active_sub_items = sponsors_customer.active_subscription_items.count
        if total_active_sub_items > 0
          units = "item".pluralize(total_active_sub_items)
          display_count = total_active_sub_items == 1 ? "an" : total_active_sub_items.to_s
          "Remove Zuora account: Cannot delete because it has #{display_count} active subscription #{units}"
        end
      end

      sig { returns ::Billing::Money }
      memoize def sponsorship_credit_balance
        sponsors_customer.credit_balance
      end
    end
  end
end
