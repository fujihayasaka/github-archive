# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class CanProceedWithUsagesController < StafftoolsController
      include Stafftools::Billing::BillingPlatformHelper

      before_action :dotcom_required

      ALLOWED_NON_GET_REQUESTS = [
        "Stafftools::Billing::CanProceedWithUsagesController#create"
      ]
      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
        "Stafftools::Billing::CanProceedWithUsagesController#create"
      ]

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
        render "stafftools/billing/can_proceed_with_usages/show", locals: {
          product_keys: product_keys,
          all_skus: all_skus,
          response: nil,
        }
      end

      def create
        customer = Customer.find(params[:customer_id])
        billable_owner = customer.billable_owner

        # Build the parameters dynamically
        cpwu_params_hash = {
          customer_id: params[:customer_id].to_s,
          product: params[:product].to_s,
          sku: params[:sku].to_s,
          quantity: params[:quantity].presence.to_f,
          repo_id: params[:repo_id].presence.to_i,
          org_id: params[:org_id].presence.to_i,
          actor_id: params[:actor_id].presence.to_i
        }

        # Conditionally add trust tier argument
        cpwu_params_hash[:trust_tier] = if FeatureFlag.vexi.enabled?(:billing_can_proceed_with_usage_trust_tier, billable_owner, default: false)
          ::TrustTiers::Tier.for_billable_owner(billable_owner).tier
        else
          0
        end

        cpwu_params = ::Billing::Platform::CanProceedWithUsage::RequestParams.new(cpwu_params_hash)

        unless cpwu_params.valid?
          flash[:error] = "Please provide value(s) for #{cpwu_params.missing_keys.to_sentence}"
          return redirect_back fallback_location: stafftools_billing_can_proceed_with_usage_path
        end

        cpwu_response = ::Billing::Platform::CanProceedWithUsage.call(cpwu_params)
        customer_response = ::Billing::Platform::Api::Client.new.get_customer(customer_id: params[:customer_id].to_s)

        error = false
        unless customer.present?
          error = true
          flash.now[:error] = "Customer #{params[:customer_id]} not found"
        end

        if customer_response.is_a?(::Billing::Platform::Api::Error)
          error = true
          flash.now[:error] = "An error happened while getting the customer"
        end

        if cpwu_response.error.present?
          error = true
          flash.now[:error] = "An error happened while checking 'canProceed' from billing platform. See 'Response' section"
        end

        response = {
          billing_platform_cpwu_response: cpwu_response,
          billing_platform_customer: customer_response,
          customer: customer,
        }

        render "stafftools/billing/can_proceed_with_usages/show", locals: {
          response: response,
          error: error,
          product_keys: product_keys,
          all_skus: all_skus,
        }
      end

      private

      def product_keys
        pricings_list = stafftools_fetch_pricing

        pricings_list.map { |p| p[:product] }.uniq.sort
      end

      def all_skus
        stafftools_fetch_pricing
      end
    end
  end
end
