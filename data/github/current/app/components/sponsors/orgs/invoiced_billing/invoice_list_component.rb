# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class InvoicedBilling::InvoiceListComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          organization: Organization,
          loader_result: Sponsors::StripeInvoicesLoader::FetchResult,
          active_sponsors_agreement: T::Boolean,
        ).void
      end
      def initialize(organization:, loader_result:, active_sponsors_agreement:)
        @organization  = organization
        @loader_result = loader_result
        @active_sponsors_agreement = active_sponsors_agreement
      end

      private

      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(Sponsors::StripeInvoicesLoader::FetchResult) }
      attr_reader :loader_result

      sig { returns(T::Boolean) }
      attr_reader :active_sponsors_agreement

      alias :active_sponsors_agreement? :active_sponsors_agreement

      sig { returns(String) }
      def blankslate_title
        case loader_result.status_filter
        when Sponsors::StripeInvoicesLoader::InvoiceStatus::Paid
          "There aren’t any paid invoices for this organization"
        else
          "There aren’t any open invoices for this organization"
        end
      end

      sig { returns(T::Boolean) }
      def show_create_button?
        return false unless active_sponsors_agreement?
        loader_result.status_filter == Sponsors::StripeInvoicesLoader::InvoiceStatus::Open
      end
    end
  end
end
