# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::StripeCustomersController < StafftoolsController
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    query = params[:q] || ""
    selected_stripe_customer_id = params[:stripe_customer_id]

    # Will be either a Stripe::SearchResultObject or an Array:
    results = if query.present?
      # See https://stripe.com/docs/search#query-fields-for-customers and https://stripe.com/docs/api/customers/search
      Stripe::Customer.search({ query: %Q(email~"#{query}" OR name~"#{query}") }, { stripe_version: "2020-08-27" })
    else
      []
    end

    render "stafftools/sponsors/stripe_customers/index", formats: :html, layout: false, locals: {
      results: results,
      error_message: nil,
      selected_stripe_customer_id: selected_stripe_customer_id,
    }
  rescue Stripe::InvalidRequestError => err
    render "stafftools/sponsors/stripe_customers/index", formats: :html, layout: false, locals: {
      results: [],
      error_message: err.message,
      selected_stripe_customer_id: selected_stripe_customer_id,
    }
  end
end
