# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class MeteredServiceLocksController < StafftoolsController
      before_action :dotcom_required
      before_action :ensure_account_exists
      before_action :ensure_account_is_invoiced, only: [:create, :destroy]

      def create
        account.lock_metered_services
        flash[:notice] = "Metered services locked"

        instrument("billing.metered_services_lock", metered_services_payload)
        redirect_to :back
      end

      def destroy
        account.unlock_metered_services
        flash[:notice] = "Metered services unlocked"

        instrument("billing.metered_services_unlock", metered_services_payload)
        redirect_to :back
      end

      private

      def account
        @account
      end

      def metered_services_payload
        {
         account.event_prefix => account,
         :customer_id => account&.customer&.id
        }
      end

      def ensure_account_is_invoiced
        unless account.invoiced?
          flash[:error] = "Only invoiced accounts can have their metered services locked"
          redirect_to :back
        end
      end

      def ensure_account_exists
        @account =
          case params[:account_type]
          when "Business"
            ::Business.find(params[:account_id])
          when "Organization"
            ::User.find(params[:account_id])
          end

        render_404 if account.nil?
      end
    end
  end
end
