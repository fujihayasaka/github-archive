# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class ProductEnablementsController < BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        ApplicationRecord::Configurations,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        render "stafftools/businesses/product_enablements/show", locals: {
          this_business: this_business
        }
      end
    end
  end
end
