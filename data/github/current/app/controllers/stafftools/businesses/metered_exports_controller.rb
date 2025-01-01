# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class MeteredExportsController < BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:index]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index],
        optional: true

      def index
        render "stafftools/businesses/metered_exports/index", locals: {
          metered_exports: this_business.metered_usage_exports.preload(:requester).order(created_at: :desc)
        }
      end

      def show
        export = this_business.metered_usage_exports.find(params[:id])

        redirect_to export.generate_expiring_url
      end

      def create
        ::Billing::MeteredReportExportJob.perform_later(current_user, this_business, params[:days].to_i)

        flash[:notice] = "We're preparing your report! We’ll attempt to send an email to #{current_user.email} when it’s ready, but the email may not work. Please refresh the page in a few minutes to see if the report has been generated."

        redirect_to stafftools_metered_exports_path(this_business)
      end

      private

      def nav_layout
        case this_user.site_admin_context
        when "organization"
          "layouts/stafftools/organization/billing"
        when "user"
          "layouts/stafftools/user/billing"
        end
      end
    end
  end
end
