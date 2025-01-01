# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotUsageController < Stafftools::Businesses::BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        client = ::Billing::Api::ClientWrapper.new(billable_owner: this_business)

        render "stafftools/businesses/copilot_usage/show", locals: {
          monthly_usage: client.copilot_monthly_usage,
        }
      end
    end
  end
end
