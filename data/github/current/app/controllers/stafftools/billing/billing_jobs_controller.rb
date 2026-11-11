# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class BillingJobsController < StafftoolsController
      include ApplicationController::VerifiedFetchDependency

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
        only: [:index]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index], optional: true

      allow_verified_fetch only: [:index]

      sig { returns(String) }
      def self.react_bundle_name
        "billing-app"
      end

      sig { void }
      def index
        render_react_app(
          payload: {
            jobs: jobs,
          },
          title: "Billing Jobs",
          layout: "layouts/stafftools/react_stafftools",
        )
      end

      private

      sig { returns(T::Array[T.class_of(ApplicationJob)]) }
      def jobs
        [
          BusinessOrganizationBillingJob
        ]
      end
    end
  end
end
