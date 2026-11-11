# typed: strict
# frozen_string_literal: true

module Businesses
  module Billing
    class AiUsageController < Businesses::BillingsController
      include ::Billing::AiUsageDependency

      T.unsafe(self).react_bundle_name = "billing-app"

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Configurations,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        only: [:index]

      before_action -> do
        T.bind(self, Businesses::Billing::AiUsageController)
        ensure_ai_usage_enabled(current_user: current_user)
      end

      sig { void }
      def index
        respond_with_ai_usage(entity: this_business)
      end
    end
  end
end
