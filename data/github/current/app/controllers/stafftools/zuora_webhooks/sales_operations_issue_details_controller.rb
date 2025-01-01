# typed: true
# frozen_string_literal: true

module Stafftools
  module ZuoraWebhooks
    class SalesOperationsIssueDetailsController < StafftoolsController
      before_action :ensure_billing_enabled

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Ballast,
        only: [:show]

      def show
        render partial: "stafftools/zuora_webhooks/sales_operations_issue_details", locals: {
          sales_operations_issue_details: webhook.sales_operations_issue_details.generate
        }
      end

      private

      def webhook
        ::Billing::ZuoraWebhook.find(params[:zuora_webhook_id])
      rescue ActiveRecord::RecordNotFound => e
        Failbot.report(e, "gh.billing.zuora.webhook_id": params[:zuora_webhook_id])
        flash[:error] = e
        redirect_back(fallback_location: "stafftools/zuora_webhooks")
      end
    end
  end
end
