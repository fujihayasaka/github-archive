# typed: strict
# frozen_string_literal: true

module Sponsors
  class CreateRecurringSponsorships
    class Result
      # Public: List of human-readable error messages describing what went wrong.
      sig { returns T::Array[String] }
      attr_reader :errors

      # Public: List of the new sponsorships that were created.
      sig { returns T::Array[Sponsorship] }
      attr_reader :sponsorships

      sig do
        params(
          errors: T::Array[String],
          sponsorships: T::Array[Sponsorship]
        ).void
      end
      def initialize(errors: [], sponsorships: [])
        @errors = errors
        @sponsorships = sponsorships
      end

      # Public: Were all sponsorships successfully made?
      sig { returns(T::Boolean) }
      def success?
        errors.empty?
      end

      # Public: How many recurring sponsorships were made?
      sig { returns(Integer) }
      def total_sponsored
        sponsorships.size
      end

      # Public: How much money was spent on recurring sponsorships that will go to maintainers?
      # Does not include fees.
      sig { returns(Billing::Money) }
      def total_amount_excluding_fees
        total_cents = sponsorships.sum(&:monthly_price_in_cents)
        Billing::Money.new(total_cents)
      end

      # Public: The users and organizations who received a sponsorship.
      sig { returns T::Array[GitHubSponsors::Types::Sponsorable] }
      def sponsorables
        sponsorships.map(&:sponsorable).compact
      end

      # Public: Did any users receive a sponsorship?
      sig { returns(T::Boolean) }
      def any_sponsored_users?
        sponsorships.any?(&:to_user?)
      end

      # Public: Did any organizations receive a sponsorship?
      sig { returns(T::Boolean) }
      def any_sponsored_organizations?
        sponsorships.any?(&:to_organization?)
      end
    end
  end
end
