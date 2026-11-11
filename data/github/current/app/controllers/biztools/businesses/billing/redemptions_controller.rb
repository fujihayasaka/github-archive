# typed: strict
# frozen_string_literal: true

class Biztools::Businesses::Billing::RedemptionsController < BiztoolsController

  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    coupon_redemptions = (current_business.coupon_redemptions + current_business.expired_coupons)
      .sort { |a, b| b.expires_at <=> a.expires_at }
      .map { |cr| [cr, cr.coupon] }
    coupon_codes = Coupon.multi_use.active.order(:code)
    render "biztools/users/billing/redemptions/index", locals: {
      account: current_business,
      stafftools_account_path: stafftools_enterprise_path(current_business),
      stafftools_account_billing_path: stafftools_enterprise_billing_path(current_business),
      coupon_revoke_path: biztools_business_revoke_coupon_path(current_business),
      coupon_redemptions: coupon_redemptions,
      passed_code: params[:coupon],
      coupon_codes: coupon_codes,
    }
  end
end
