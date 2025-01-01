# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::TransfersPreviewPartialsController < StripeConnectAccountsController
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
      only: [:show], optional: true

    TRANSFERS_PREVIEW_LIMIT = 15
    TRANSFERS_FILTER_LIMIT = 50

    def show
      layout = if request.xhr? || pjax?
        false
      else
        "application"
      end

      render(Stafftools::Sponsors::Members::Transfers::ListComponent.new(
        sponsorable_login: this_sponsorable.login,
        stripe_account: stripe_connect_account,
        page: current_page,
        limit: params[:sponsor].present? ? TRANSFERS_FILTER_LIMIT : TRANSFERS_PREVIEW_LIMIT,
        paginate: params[:paginate] == "1",
        starting_after: params[:starting_after],
        ending_before: params[:ending_before],
        sponsor: params[:sponsor],
      ), layout: layout)
    end
  end
end
