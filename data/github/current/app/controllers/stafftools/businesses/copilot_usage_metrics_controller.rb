# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotUsageMetricsController < Stafftools::Businesses::BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:show]

      def show
        usage_metrics = ::Copilot::Metrics::UsageMetrics.new(business: this_business)

        respond_to do |format|
          format.json do
            render json: usage_metrics.usage_details, status: 200
          end
          format.html do
            render "stafftools/businesses/copilot_usage_metrics/show", locals: {
              copilot_business: copilot_business,
              details: usage_metrics.usage_details,
            }
          end
        end
      end

      private

      memoize def copilot_business
        ::Copilot::Business.new(this_business)
      end
    end
  end
end
