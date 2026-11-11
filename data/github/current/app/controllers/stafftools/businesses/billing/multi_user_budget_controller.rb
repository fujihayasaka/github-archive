# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::MultiUserBudgetController < Stafftools::Businesses::BillingController
  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show, :index]

  allow_verified_fetch only: [:show, :index]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def show
    render_multi_user_budget(
      this_entity: this_business,
      is_stafftools_route: true,
    )
  end

  sig { void }
  def index
    render_multi_user_budget_states(this_entity: this_business)
  end
end
