# typed: strict
# frozen_string_literal: true

module Stafftools
  module Users
    module Billing
      class InformationController < BillingController
        include Stafftools::Billing::Information::SharedControllerMethods

        depends_on_clusters ApplicationRecord::Ballast,
          ApplicationRecord::Billing,
          ApplicationRecord::Collab,
          ApplicationRecord::Copilot,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Repositories
        CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
          "Stafftools::Users::Billing::InformationController#create",
        ].freeze, T::Array[String])

        sig { void }
        def index
          render "stafftools/users/billing/information/index"
        end

        private

        sig { override.params(params: T::Hash[String, String]).void }
        def redirect_to_information_path(params)
          redirect_to stafftools_user_billing_information_index_path(this_user, **params)
        end
      end
    end
  end
end
