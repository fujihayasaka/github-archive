# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::DiscountsController < Stafftools::Users::BillingController
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Billing::DiscountsDependency

  before_action :ensure_vnext_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
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
    render_discounts_index(this_entity: this_entity, is_stafftools_route: true)
  end

  sig { void }
  def create
    handle_discount_create(entity: this_user, customer_id: this_user.customer.id.to_s)
  end
end
