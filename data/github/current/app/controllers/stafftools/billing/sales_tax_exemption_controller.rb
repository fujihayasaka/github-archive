# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class SalesTaxExemptionController < StafftoolsController
      extend T::Sig

      before_action :dotcom_required

      sig { void }
      def update
        status = params[:status]
        status_reason = params[:status_reason]
        account_type = params[:account_type]
        account_id = params[:id]

        account = find_account(account_type, account_id)
        return render_404 if account.blank?

        stafftools_billing_settings_page = stafftools_account_path(account, account_type)
        customer = account.customer

        return redirect_to(stafftools_billing_settings_page, alert: "Account is missing customer record.") if customer.nil?
        tax_exemption_status = customer.tax_exemption_status
        return redirect_to(stafftools_billing_settings_page, alert: "Customer is missing tax exemption status record.") if tax_exemption_status.nil?

        if tax_exemption_status.update(status: status, status_reason: status_reason)
          notify_customer_of_rejection(tax_exemption_status) if tax_exemption_status.rejected?

          redirect_to stafftools_billing_settings_page, notice: "Tax exemption status updated"
        else
          flash[:error] = tax_exemption_status.errors.full_messages.to_sentence

          redirect_to stafftools_billing_settings_page
        end
      end

      private

      sig { params(tax_exemption_status: ::Billing::TaxExemptionStatus).void }
      def notify_customer_of_rejection(tax_exemption_status)
        return unless tax_exemption_status.rejected?

        BillingNotificationsMailer.tax_exemption_certificate_rejected(tax_exemption_status).deliver_later
      end

      sig { params(account_type: String, account_id: String).returns(T.nilable(T.any(::Business, ::Organization))) }
      def find_account(account_type, account_id)
        if account_type == "Business"
          ::Business.find_by(slug: account_id)
        elsif account_type == "Organization"
          ::Organization.find_by(login: account_id)
        end
      end

      sig { params(account: ::Billing::Types::OrgOrBusiness, account_type: String).returns(String) }
      def stafftools_account_path(account, account_type)
        return stafftools_enterprise_billing_path(account) if account_type == "Business"

        billing_stafftools_user_path(account)
      end
    end
  end
end
