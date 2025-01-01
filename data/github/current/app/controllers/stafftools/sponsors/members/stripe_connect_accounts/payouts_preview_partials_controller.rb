# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::PayoutsPreviewPartialsController < StripeConnectAccountsController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

    PAYOUTS_PREVIEW_LIMIT = 15

    def show
      render(Stafftools::Sponsors::Members::Payouts::ListComponent.new(
        stripe_account: stripe_connect_account,
        limit: PAYOUTS_PREVIEW_LIMIT,
      ), layout: false)
    end
  end
end
