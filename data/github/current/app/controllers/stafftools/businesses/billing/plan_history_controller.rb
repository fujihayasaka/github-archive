# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PlanHistoryController < Stafftools::Businesses::BillingController
  PER_PAGE = 10

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index]

  sig { void }
  def index
    render_404 unless business = this_business
    plan_history = fetch_plan_history(T.must(business))
    render "stafftools/businesses/plan_history", locals: { business: business, plan_history: plan_history }
  end

  private

  sig { returns(T.nilable(Business)) }
  def this_business
    slug = params[:slug] || params[:enterprise_slug]
    ::Business.find_by(slug: slug)
  end

  sig { params(business: Business).returns(T::Array[T.untyped]) }
  def fetch_plan_history(business)
    customer = business.customer
    return [] unless customer

    customer.billing_transactions
    .select(
      :transaction_type,
      :seats_total,
      :seats_delta,
      :plan_name,
      :old_plan_name,
      :asset_packs_total,
      :asset_packs_delta,
      :created_at
    )
    .order(created_at: :desc)
    .paginate(page: current_page, per_page: PER_PAGE)
    .to_a
  end
end
