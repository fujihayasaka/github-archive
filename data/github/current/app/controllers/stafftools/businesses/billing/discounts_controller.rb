# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::DiscountsController < Stafftools::Businesses::BillingController
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Billing::DiscountsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:index, :create]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def index
    render_discounts_index(this_entity: this_business, is_stafftools_route: true)
  end

  def create
    handle_discount_create(entity: this_business, customer_id: this_business.customer_id.to_s)
  end
end
