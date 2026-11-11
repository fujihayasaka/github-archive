# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class GenerateUsagesController < StafftoolsController
      include Stafftools::Billing::BillingPlatformHelper

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

      depends_on_clusters ApplicationRecord::Authnd,
        ApplicationRecord::Copilot,
        only: [:show],
        optional: true

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w(
        Stafftools::Billing::GenerateUsagesController#create
      )

      def show
        enforce_positive_inputs = FeatureFlag.vexi.enabled?(:stafftools_billing_positive_integer_inputs, default: false)
        render "stafftools/billing/generate_usages/show", locals: {
          product_keys: product_keys,
          all_skus: all_skus,
          enforce_positive_inputs: enforce_positive_inputs,
        }
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

        if !params[:source_uri].present?
          flash[:error] = "Please provide a source URI"
          redirect_to(action: :show)
          return
        end

        req_params = get_usage_params

        entity = {
          customer_id: req_params[:customer_id],
          repo_id: req_params[:repo_id],
          organization_id: req_params[:org_id],
          actor_id: req_params[:actor_id],
        }

        metadata = {}
        metadata[:copilot_model] = req_params[:copilot_model] if req_params[:copilot_model].present?
        metadata[:copilot_plan] = req_params[:copilot_plan].to_sym if req_params[:copilot_plan].present?
        entity[:metadata] = metadata if metadata.any?

        usage_payload = {
          sku: req_params[:sku],
          quantity: req_params[:quantity],
          usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
          source_uri: req_params[:source_uri],
          entity: entity,
        }

        if req_params[:non_billable]
          usage_payload[:non_billable] = true
        end

        GlobalInstrumenter.instrument("billing_platform.metered_usage", usage_payload)

        flash[:notice] = "Usage sent for ingestion"

        redirect_to(action: :show)
      end

      private

      def get_usage_params
        customer_id = params[:customer_id].presence || 0
        sku = params[:sku].presence || ""
        source_uri = params[:source_uri].presence || ""
        org_id = params[:org_id].presence || 0
        repo_id = params[:repo_id].presence || 0
        quantity = params[:quantity].presence || 0.0
        actor_id = params[:actor_id].presence || 0
        copilot_model = params[:copilot_model].presence
        copilot_plan = params[:copilot_plan].presence
        non_billable = params[:non_billable] == "1"
        {
          customer_id: customer_id.to_i,
          sku: sku.to_s,
          source_uri: source_uri.to_s,
          org_id: org_id.to_i,
          repo_id: repo_id.to_i,
          quantity: quantity.to_f,
          actor_id: actor_id.to_i,
          copilot_model: copilot_model&.to_s,
          copilot_plan: copilot_plan&.to_s,
          non_billable: non_billable,
        }
      end

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
