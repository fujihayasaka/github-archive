# typed: strict
# frozen_string_literal: true


module Stafftools
  module Businesses
    class CopilotMetricsController < Stafftools::Businesses::BusinessBaseController
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

      sig { void }
      def show
        copilot_metrics = ::Copilot::Metrics::CopilotMetrics.new(business: this_business)

        respond_to do |format|
          format.json do
            render json: copilot_metrics.payload, status: 200
          end
          format.html do
            render "stafftools/businesses/copilot_metrics/show", locals: {
              copilot_business: copilot_business,
              details: copilot_metrics.payload,
            }
          end
        end
      end

      private

      sig { returns(::Copilot::Business) }
      memoize def copilot_business
        ::Copilot::Business.new(this_business)
      end
    end
  end
end
