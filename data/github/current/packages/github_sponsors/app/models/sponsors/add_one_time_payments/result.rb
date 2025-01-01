# typed: strict
# frozen_string_literal: true

module Sponsors
  class AddOneTimePayments
    class Result
      extend T::Sig

      # Public: List of human-readable error messages describing what went wrong.
      sig { returns T::Array[String] }
      attr_reader :errors

      # Public: List of the new sponsorships that were created.
      sig { returns T::Array[Sponsorship] }
      attr_reader :sponsorships

      # Public: List of new subscription items that were created when an active sponsorship was already present.
      # Not exhaustive; will not include subscription items for any sponsorship in `sponsorships`.
      sig { returns T::Array[Billing::SubscriptionItem] }
      attr_reader :subscription_items

      sig do
        params(
          errors: T::Array[String],
          sponsorships: T::Array[Sponsorship],
          subscription_items: T::Array[Billing::SubscriptionItem],
        ).void
      end
      def initialize(errors: [], sponsorships: [], subscription_items: [])
        @errors = errors
        @sponsorships = sponsorships
        @subscription_items = subscription_items
      end

      # Public: Were all one-time payments successfully made?
      sig { returns(T::Boolean) }
      def success?
        errors.empty?
      end

      # Public: How many one-time payments were made?
      sig { returns(Integer) }
      def total_sponsored
        sponsorships.size + subscription_items.size
      end

      # Public: How much money was spent on one-time payments that will go to maintainers?
      # Does not include fees.
      sig { returns(Billing::Money) }
      def total_amount_excluding_fees
        total_cents = sponsorships.sum(&:monthly_price_in_cents) +
          Billing::SubscriptionItem.total_monthly_price_in_cents(subscription_items, include_fees: false)
        Billing::Money.new(total_cents)
      end

      # Public: The users and organizations who received a one-time payment.
      sig { returns T::Array[GitHubSponsors::Types::Sponsorable] }
      def sponsorables
        sponsorships.map(&:sponsorable).compact + subscription_items.map(&:sponsorable).compact
      end

      # Public: Did any users receive a sponsorship?
      sig { returns(T::Boolean) }
      def any_sponsored_users?
        sponsorships.any?(&:to_user?) || subscription_items.any?(&:sponsored_user?)
      end

      # Public: Did any organizations receive a sponsorship?
      sig { returns(T::Boolean) }
      def any_sponsored_organizations?
        sponsorships.any?(&:to_organization?) || subscription_items.any?(&:sponsored_organization?)
      end
    end
  end
end
