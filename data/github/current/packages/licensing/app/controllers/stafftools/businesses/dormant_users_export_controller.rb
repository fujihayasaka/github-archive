# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class DormantUsersExportController < Stafftools::Businesses::BusinessBaseController
      include DormantUsersExportHelper

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        only: [:index]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        only: [:show]

      def index
        user_dormancy_reports = GHECAdmin::EnterpriseDormantUsersExport.latest_for_business(business: this_business, include_stafftools_reports: true)

        if user_dormancy_reports.any?(&:in_progress?)
          # Return 202 to signal to poll-include-fragment to keep polling
          return head 202
        end

        render partial: "businesses/settings/dormant_users_export/index", locals: {
          business: this_business,
          for_stafftools: true,
          reports: user_dormancy_reports,
          reports_url: dormant_users_exports_stafftools_enterprise_path(this_business)
        }
      end

      # This downloads a finished report
      def show
        export = this_business.business_report_exports.find_by!(token: params[:token], report_type: report_type)
        render_export(export: export, stat_name: "dormant_users_export")
      end

      def create
        options = {
          actor: current_user,
          report_type: report_type,
          triggered_via_stafftools: true
        }
        this_business.business_report_exports.create!(options)

        render status: :created, partial: "businesses/settings/dormant_users_export/create", locals: {
          business: this_business,
          for_stafftools: true,
          reports: GHECAdmin::EnterpriseDormantUsersExport.latest_for_business(business: this_business, include_stafftools_reports: true),
          reports_url: dormant_users_exports_stafftools_enterprise_path(this_business)
        }
      end

      def destroy
        business_report = this_business.business_report_exports.find_by!(id: params[:id])
        begin
          business_report.destroy!
          flash[:notice] = "Your dormant users report has been deleted."
        rescue ActiveRecord::ActiveRecordError => error
          Failbot.report(error, {
            repository_id: current_repository.id
          })
          flash[:error] = "Unable to delete the dormant users report."
        ensure
          redirect_to :back
        end
      end
    end
  end
end
