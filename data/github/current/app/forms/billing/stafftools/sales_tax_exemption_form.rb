# typed: strict
# frozen_string_literal: true

module Billing
  module Stafftools
    class SalesTaxExemptionForm < ApplicationForm

      sig { returns(Billing::TaxExemptionStatus) }
      attr_reader :tax_exemption_status

      sig { params(account: Billing::Types::OrgOrBusiness, tax_exemption_status: Billing::TaxExemptionStatus).void }
      def initialize(account:, tax_exemption_status:)
        @account = account
        @tax_exemption_status = T.let(tax_exemption_status, Billing::TaxExemptionStatus)
      end

      sig { returns(String) }
      def account_type
        T.must(@account.class.name)
      end

      sig { params(option: String).returns(T::Boolean) }
      def is_checked?(option)
        tax_exemption_status.status == option
      end

      form do |form|
        T.bind(self, SalesTaxExemptionForm)

        form.hidden(name: "account_type", value: account_type)
        form.radio_button_group(name: "status", label: "Status (last updated: #{tax_exemption_status.updated_at})") do |radio_group|
          radio_group.radio_button(value: "approved", checked: is_checked?("approved"), label: "Approved")
          radio_group.radio_button(value: "rejected", checked: is_checked?("rejected"), label: "Rejected")
        end
        form.text_area(name: "status_reason", label: "Reason (to be included in email sent to customer)", cols: 60, rows: 3, value: tax_exemption_status.status_reason)

        form.submit(name: "submit", label: "Save")
      end
    end
  end
end
