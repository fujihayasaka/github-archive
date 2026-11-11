# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::CopilotUsage::ModelsController < Stafftools::Users::BillingController
  include Billing::ModelsDependency

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
    ApplicationRecord::Ballast,
    only: [:index]

  sig { void }
  def index
    render_models_data(this_entity: this_entity)
  end
end
