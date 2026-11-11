# typed: strict
# frozen_string_literal: true

class Businesses::Billing::MultiUserBudgetsController < Businesses::BillingsController
  T.unsafe(self).react_bundle_name = "billing-app"

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:show, :index]

  allow_verified_fetch only: [:show, :index]

  sig { void }
  def show
    add_client_feature_flag([:billing_user_level_budgets_manage])

    render_multi_user_budget(
      this_entity: this_business,
      layout: "react_business",
    )
  end

  sig { void }
  def index
    render_multi_user_budget_states(this_entity: this_business)
  end
end
