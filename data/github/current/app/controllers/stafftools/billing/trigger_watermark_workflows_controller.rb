# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class TriggerWatermarkWorkflowsController < StafftoolsController
      extend T::Sig

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
        only: [:show, :trigger]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show],
        optional: true

      def show
        render("stafftools/billing/trigger_watermark_workflow/show")
      end

      def trigger # rubocop:todo GitHub/UseRestfulActions
        if !params[:workflow_datetime].present?
          flash[:error] = "Please choose a date & time for the workflow"
          redirect_to(action: :show)
          return
        end

        req_params = get_workflow_params
        response = ::Billing::Platform::Api::Client.new.admin_trigger_watermark_workflow(**req_params)

        if response.is_a?(::Billing::Platform::Api::Error)
          flash[:error] = "Failed to trigger watermark workflow"
        else
          customer_text = req_params[:customer_id].present? ? " customer #{req_params[:customer_id]}" : " all customers"
          workflow_datetime = "#{req_params[:year]}-#{req_params[:month]}-#{req_params[:day]} at #{req_params[:hour]}:00"

          flash[:notice] = "Watermark workflow is being processed for #{customer_text} on #{workflow_datetime}"
        end

        redirect_to(action: :show)
      end

      private

      def get_workflow_params
        workflow_run_time = DateTime.parse(params[:workflow_datetime])
        customer_id = params[:workflow_customer_id].presence || ""
        sku = params[:workflow_sku].presence || ""

        {
          year: workflow_run_time.year.to_i,
          month: workflow_run_time.month.to_i,
          day: workflow_run_time.day.to_i,
          hour: workflow_run_time.hour.to_i,
          customer_id: customer_id.to_s,
          sku: sku.to_s,
        }
      end
    end
  end
end
