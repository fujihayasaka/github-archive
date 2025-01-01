# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::NetUsagesController < Stafftools::Businesses::BillingController
  include Billing::Platform::Api::Utils
  include Billing::NetUsagesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    render_net_usages(
        this_entity: this_business,
        current_user: current_user,
        is_stafftools_route: true
      )
  end

  private

  sig { override.returns(Business) }
  def this_entity
    this_business
  end
end
