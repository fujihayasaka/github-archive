# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class CanProceedWithUsagesController < StafftoolsController
      extend T::Sig

      before_action :dotcom_required
      before_action :validate_params, only: [:create]

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
        render "stafftools/billing/can_proceed_with_usages/show", locals: { response: nil }
      end

      def create
        response = ::Billing::Platform::Api::Client.new.can_proceed_with_usage(usage_key: get_usage_key)

        if response.is_a?(::Billing::Platform::Api::Error)
          flash.now[:error] = "An error happened while checking 'canProceed' from billing platform. See 'Response' section"
        end

        render "stafftools/billing/can_proceed_with_usages/show", locals: { response: response }
      end

      private

      def get_usage_key
        entity_detail = BillingPlatform::Base::EntityDetail.new(
          customerId: params[:customer_id].to_s,
          repoId: params[:repo_id].presence.to_i,
          ownerId: params[:org_id].presence.to_i,
          actorId: params[:actor_id].presence.to_i,
        )

        usage_key = BillingPlatform::Api::V1::UsageKey.new(
          product: params[:product].to_s,
          sku: params[:sku].to_s,
          entityDetail: entity_detail,
          usageAt: Time.now.utc.to_i,
          quantity: params[:quantity].presence.to_f # currently unused, see https://github.com/github/billing-platform/blob/main/docs/can_proceed_with_usage.md#usage
        )

        usage_key
      end

      def validate_params
        missing = []

        if !params[:customer_id].present?
          missing << "customer ID"
        end

        if !params[:sku].present?
          missing << "sku"
        end

        if !params[:product].present?
          missing << "product"
        end

        if missing.any?
          flash.now[:error] = "Please provide value(s) for #{missing.to_sentence}"
          render "stafftools/billing/can_proceed_with_usages/show", locals: { response: nil }
        end
      end
    end
  end
end
