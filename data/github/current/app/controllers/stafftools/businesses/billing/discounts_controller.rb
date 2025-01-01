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
    response = billing_platform_client.create_discount(discount: discount_params)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to create discount" }, status: 500
    end
    audit_log_payload = {
      actor: current_user,
      business: this_business,
      customer_id: this_business.customer_id.to_s,
      targets: discount_params["targets"],
    }
    GitHub.instrument("billing.discounts_create", audit_log_payload)
    render_react_app payload: {}
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def discount_params
    body = JSON.parse(T.must(request).body.read).symbolize_keys.slice(*%i(customerId endDate percentage startDate targets targetAmount))
    body[:customerId] = body[:customerId].to_s if body[:customerId]
    body[:targets] = body[:targets].map { |target| { id: target["id"].to_s, type: target["type"] } } if body[:targets]
    body
  end
end
