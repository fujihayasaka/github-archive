# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class MarketplaceController < Stafftools::Businesses::BusinessBaseController
      skip_before_action :dotcom_required, only: %i(index)

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        only: [:index]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index],
        optional: true

      def index
        render "stafftools/businesses/marketplace/index", locals: {
          marketplace_items: this_business
            .get_plan_subscription_or_null_plan
            .active_marketplace_listing_subscription_items
            .includes(subscribable: [listing: [:listing_plans]])
            .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
        }
      end
    end
  end
end
