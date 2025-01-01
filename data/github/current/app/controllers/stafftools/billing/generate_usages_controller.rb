# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class GenerateUsagesController < StafftoolsController

      before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Ballast,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories,
        ApplicationRecord::Configurations,
        only: [:show, :create]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show],
        optional: true

      def show
        render("stafftools/billing/generate_usages/show")
      end

      def create
        if !params[:customer_id].present?
          flash[:error] = "Please provide a customer ID"
          redirect_to(action: :show)
          return
        end

        if !params[:sku].present?
          flash[:error] = "Please provide a sku"
          redirect_to(action: :show)
          return
        end

        req_params = get_usage_params
        response = ::Billing::Platform::Api::Client.new.admin_generate_usage(**req_params)

        if response.is_a?(::Billing::Platform::Api::Error)
          flash[:error] = "Failed to generate usage"
        else
          flash[:notice] = "Usage sent for ingestion"
        end

        redirect_to(action: :show)
      end

      private

      def get_usage_params
        customer_id = params[:customer_id].presence || ""
        sku = params[:sku].presence || ""
        org_id = params[:orgId].presence || 0
        repo_id = params[:repoId].presence || 0
        amount = params[:amount].presence || 0.0
        quantity = params[:quantity].presence || 0.0

        {
          customer_id: customer_id.to_s,
          sku: sku.to_s,
          org_id: org_id.to_i,
          repo_id: repo_id.to_i,
          amount: amount.to_f,
          quantity: quantity.to_f,
        }
      end
    end
  end
end
