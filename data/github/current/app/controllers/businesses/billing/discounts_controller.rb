# typed: true
# frozen_string_literal: true

class Businesses::Billing::DiscountsController < Businesses::BillingsController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include Billing::DiscountsDependency

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
    render_discounts_index(this_entity: this_business)
  end
end
