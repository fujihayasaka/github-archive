# typed: true
# frozen_string_literal: true

class Customers::Billing::DiscountsController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include Billing::DiscountsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    render_discounts_index(this_entity: this_entity)
  end
end
