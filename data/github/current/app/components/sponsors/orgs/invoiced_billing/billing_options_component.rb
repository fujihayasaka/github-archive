# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class InvoicedBilling::BillingOptionsComponent < ApplicationComponent
      extend T::Sig

      sig { params(organization: Organization).void }
      def initialize(organization:)
        @organization = organization
      end

      private

      sig { returns(Organization) }
      attr_reader :organization

      # Private: Indicates if the organization has configured invoicing for sponsorships.
      sig { returns(T::Boolean) }
      memoize def sponsors_invoiced?
        organization.sponsors_invoiced?
      end

      # Private: Indicates if the organization has configured invoiced billing for their GitHub account plan.
      sig { returns(T::Boolean) }
      memoize def github_invoiced?
        organization.invoiced?
      end

      sig { returns(T::Boolean) }
      def credit_card?
        return false if github_invoiced?
        !sponsors_invoiced?
      end
    end
  end
end
