# typed: strict
# frozen_string_literal: true

class Biztools::Coupons::ZuoraSyncsController < BiztoolsController
  before_action :ensure_coupon_exists

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Biztools::Coupons::ZuoraSyncsController#create",
  ].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing

  sig { void }
  def create
    coupon = T.must(this_coupon)
    coupon.sync_to_zuora

    flash[:notice] = "Zuora sync for coupon '#{coupon}' has been triggered successfully."
  rescue StandardError => e
    flash[:error] = "Zuora sync failed for coupon '#{coupon}': #{e.message}"
  ensure
    redirect_to biztools_coupon_path(coupon)
  end

  private

  sig { returns(T.nilable(Coupon)) }
  memoize def this_coupon
    ::Coupon.find_by_code(params[:coupon_id])
  end

  sig { void }
  def ensure_coupon_exists
    render_404 if this_coupon.nil?
  end
end
