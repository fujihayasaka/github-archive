# typed: strict
# frozen_string_literal: true

# This controller is not implemented yet.
class Stafftools::Users::Billing::BudgetsController < Stafftools::Users::BillingController
  T.unsafe(self).react_bundle_name = "billing-app"

  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

  before_action :ensure_vnext_enabled

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
    ApplicationRecord::Ballast,
    only: [:index]

  sig { void }
  def index
    render_budgets(this_entity: this_user, layout: react_layout, is_stafftools_route: true)
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def budget_request_params
    JSON.parse(request.body.read)
  end
end
