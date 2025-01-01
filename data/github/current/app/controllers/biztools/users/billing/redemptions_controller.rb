# typed: true
# frozen_string_literal: true

class Biztools::Users::Billing::RedemptionsController < BiztoolsController
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

  def index
    coupon_redemptions = (current_account.coupon_redemptions + current_account.expired_coupons)
      .sort { |a, b| b.expires_at <=> a.expires_at }
      .map { |cr| [cr, cr.coupon] }
    coupon_codes = Coupon.multi_use.active.order(:code)
    render "biztools/users/billing/redemptions/index", locals: {
      account: current_account,
      stafftools_account_path: stafftools_user_path(current_account),
      stafftools_account_billing_path: billing_stafftools_user_path(current_account),
      coupon_revoke_path: biztools_user_coupon_path(current_account),
      coupon_redemptions: coupon_redemptions,
      passed_code: params[:coupon],
      coupon_codes: coupon_codes,
    }
  end
end
