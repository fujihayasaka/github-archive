# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageTotalsController < Stafftools::Users::BillingController
  include Billing::UsageTotalsDependency

  before_action :ensure_vnext_enabled

  depends_on_clusters ApplicationRecord::Ballast,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render_usage_totals_data(this_entity: this_user, is_stafftools_route: true)
  end
end
