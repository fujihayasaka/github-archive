# typed: strict
# frozen_string_literal: true

module Businesses
  module Billing
    class PremiumRequestsUsageController < Businesses::BillingsController
      include ::Billing::PremiumRequestsUsageDependency

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
        T.bind(self, Businesses::Billing::PremiumRequestsUsageController)
        ensure_pru_page_enabled(entity: this_business)
      end
      # disable inherited before_action since it allows access for org owners
      skip_before_action :require_business_access
      before_action -> do
        T.bind(self, Businesses::Billing::PremiumRequestsUsageController)
        business_access_required(allow_org_owners: FeatureFlag.vexi.enabled?(:pru_billing_page_org_admins, this_business, default: false))
      end

      sig { void }
      def index
        add_client_feature_flag([:billing_show_top_100_users_usage_table], entity: this_business)
        add_client_feature_flag([:show_billing_pru_progress_bars], entity: this_business)
        render_premium_requests_usage(entity: this_business, current_user: current_user)
      end
    end
  end
end
