# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::BalancePartialsController < StripeConnectAccountsController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show], optional: true

    def show
      response = stripe_connect_account.current_balance
      render partial: "stafftools/sponsors/members/stripe_balance", locals: {
        response: response,
      }
    end
  end
end
