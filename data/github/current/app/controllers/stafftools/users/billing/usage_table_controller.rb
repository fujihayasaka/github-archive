# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageTableController < Stafftools::Users::BillingController
  include ApplicationController::VerifiedFetchDependency
  include Billing::UsageTable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:index]

  sig { void }
  def index
    render_usage_table_data(this_entity: this_user, is_stafftools_route: true)
  end
end
