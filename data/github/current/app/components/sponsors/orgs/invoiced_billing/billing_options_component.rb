# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class InvoicedBilling::BillingOptionsComponent < ApplicationComponent
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

      # Whether or not this is a sponsorship created by an org in a self-serve enterprise
      #
      # Returns true if:
      #   - the sponsor is an org managed by an enterprise
      #   - that enterprise is self served
      sig { returns T::Boolean }
      memoize def self_serve_enterprise?
        business = Business.from_org_id(organization.id)
        business.present? && business.self_serve_payment?
      end

      sig { returns T::Boolean }
      memoize def restricted_enterprise?
        organization.has_commercial_interaction_restriction?
      end
    end
  end
end
