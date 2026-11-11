# typed: strict
# frozen_string_literal: true

module Businesses
  module Billing
    class PremiumRequestsUsageController < Businesses::BillingsController
      include ::Billing::PremiumRequestsUsageDependency

      T.unsafe(self).react_bundle_name = "billing-app"

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Authnd,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Configurations,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        only: [:index]

      before_action -> do
        T.bind(self, Businesses::Billing::PremiumRequestsUsageController)
        ensure_pru_page_enabled(entity: this_business)
      end

      sig { void }
      def index
        render_premium_requests_usage(entity: this_business, current_user: current_user)
      end
    end
  end
end
