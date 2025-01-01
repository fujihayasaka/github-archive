# typed: true
# frozen_string_literal: true

class Customers::Billing::NetUsagesController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include Customers::Billing::Concerns::NetUsages

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
    only: [:index]

  def index
    render_net_usages(this_entity: this_entity)
  end
end
