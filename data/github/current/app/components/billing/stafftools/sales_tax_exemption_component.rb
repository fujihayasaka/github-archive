# typed: strict
# frozen_string_literal: true

module Billing
  module Stafftools
    class SalesTaxExemptionComponent < ApplicationComponent
      extend T::Sig

      sig { returns(Billing::Types::OrgOrBusiness) }
      attr_reader :account

      sig { params(account: Billing::Types::OrgOrBusiness).void }
      def initialize(account:)
        @account = account
      end

      sig { returns(String) }
      def entity_type
        return "Business" if account.business?

        "Organization"
      end

      sig { returns(T.nilable(Billing::TaxExemptionStatus)) }
      memoize def tax_exemption_status
        account.customer&.tax_exemption_status
      end
    end
  end
end
