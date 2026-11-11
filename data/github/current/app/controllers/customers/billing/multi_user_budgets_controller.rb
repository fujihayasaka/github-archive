# typed: true
# frozen_string_literal: true

class Customers::Billing::MultiUserBudgetsController < Customers::BillingController
  T.unsafe(self).react_bundle_name = "billing-app"

  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

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
    only: [:show, :index]

  allow_verified_fetch only: [:show, :index]

  before_action :ensure_organization_path

  sig { void }
  def show
    add_client_feature_flag([:billing_user_level_budgets_manage]) # rubocop:disable GitHub/NoReactAppPayload

    render_multi_user_budget(
      this_entity: this_entity,
      layout: react_layout
    )
  end

  sig { void }
  def index
    render_multi_user_budget_states(this_entity: this_entity)
  end

  private

  sig { void }
  def ensure_organization_path
    render_404 if individual_path?
  end
end
