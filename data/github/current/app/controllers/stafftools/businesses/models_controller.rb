# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ModelsController < Stafftools::Businesses::BusinessBaseController
  include GitHubModels::PlaygroundDependency
  include GitHubModels::BillingDependency

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: %i(show)

  def show
    render "stafftools/businesses/models/show", locals: {
      business: this_business,
      models_enabled: this_business.models_access_enabled?,
      can_show_models_billing: this_business.can_show_models_billing?,
      can_enable_models_billing: this_business.can_enable_models_billing?,
      has_payment_method: this_business.has_payment_method?,
      enabled_models_billing: this_business.models_billing_enabled?,
      billing_enabled: this_business.models_billing_enabled?,
      models_billing_disabled_by_non_payment_method_reason: this_business.models_billing_disabled_by_non_payment_method_reason?,
    }
  end
end
