# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageTableController < Businesses::BillingsController
  include ApplicationController::VerifiedFetchDependency
  include Billing::UsageTable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:index]

  sig { void }
  def index
    render_usage_table_data(this_entity: this_business)
  end
end
