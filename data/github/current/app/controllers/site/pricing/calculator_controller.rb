# typed: true
# frozen_string_literal: true

class Site::Pricing::CalculatorController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  javascript_bundle "pricing-calculator"
  stylesheet_bundle "pricing-calculator"

  def index
    analytics_event(
      category: "Pricing Calculator",
      action: "Page load",
    )

    render "site/pricing/calculator/index"
  end
end
