# typed: strict
# frozen_string_literal: true

class Businesses::OneTimePaymentController < Businesses::BusinessController
  extend T::Sig

  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_is_billable
  before_action :ensure_positive_balance
  before_action :business_access_required
  before_action :ensure_autopay_disabled_by_rbi
  before_action :ensure_self_serve_payment_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:new]

  javascript_bundle :billing, :"billing-settings"

  stylesheet_bundle :settings

  sig { void }
  def new
    purpose = params[:purpose]&.to_sym
    manual_payment = Billing::ManualPayment.new(target: this_business, purpose: purpose)

    render "billing_settings/payments/separate", locals: {
      target: this_business,
      trade_screening_needed: true,
      manual_payment: manual_payment
    }
  end

  private

  sig { void }
  def ensure_positive_balance
    unless this_business.latest_bill_balance.positive?
      flash[:error] = "No outstanding balance to pay"
      redirect_to settings_billing_enterprise_path(this_business)
    end
  end

  sig { void }
  def ensure_target
    render_404 unless this_business
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless this_business.billable?
  end

  sig { void }
  def ensure_autopay_disabled_by_rbi
    render_404 unless this_business.autopay_disabled_by_india_rbi?
  end

  sig { void }
  def ensure_self_serve_payment_enabled
    render_404 unless this_business.self_serve_payment?
  end
end
