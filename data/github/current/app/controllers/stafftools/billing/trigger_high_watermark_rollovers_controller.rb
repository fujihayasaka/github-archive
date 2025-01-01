# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class TriggerHighWatermarkRolloversController < StafftoolsController
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
        render("stafftools/billing/trigger_high_watermark_rollover/show")
      end

      def trigger # rubocop:todo GitHub/UseRestfulActions
        if !params[:rollover_month].present? || !params[:rollover_year].present?
          flash[:error] = "Please choose a year & month for the job"
          redirect_to(action: :show)
          return
        end

        req_params = get_workflow_params
        response = ::Billing::Platform::Api::Client.new.admin_trigger_high_watermark_rollover(**req_params)

        if response.is_a?(::Billing::Platform::Api::Error)
          flash[:error] = "Failed to trigger high watermark rollover"
        else
          rollover_datetime = "#{req_params[:year]}-#{req_params[:month]}"
          flash[:notice] = "High watermark rollover is being processed for #{req_params[:customer_id]} on #{rollover_datetime}"
        end

        redirect_to(action: :show)
      end

      private

      def get_workflow_params
        {
          year: params[:rollover_year].to_i,
          month: params[:rollover_month].to_i,
          customer_id: params[:customer_id].to_s,
          sku: params[:sku].to_s,
          dry_run: params[:dry_run].to_i == 1
        }
      end
    end
  end
end
