# typed: strict
# frozen_string_literal: true

class BillingSettings::PaymentsController < ApplicationController

  include BillingSettingsHelper
  include OrganizationsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_is_billable
  before_action :disable_color_modes
  before_action do
    T.bind(self, BillingSettings::PaymentsController)

    check_trade_compliance(target: target)
  end
  before_action :ensure_positive_balance, only: [:new]

  javascript_bundle :billing, :"billing-settings"

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

  sig { void }
  def check # rubocop:todo GitHub/UseRestfulActions
    return head 404 if !request.xhr? || params[:payment_id].blank?

    if target.billing_transactions.exists?(platform_transaction_id: params[:payment_id])
      head 200
    else
      head 202
    end
  end

  sig { void }
  def new
    if !target.autopay_disabled_by_india_rbi?
      flash[:error] = "Manual payments are not allowed for this account"
      return redirect_to target_billing_url(target)
    end

    purpose = params[:purpose]&.to_sym
    manual_payment = Billing::ManualPayment.new(target: target, purpose: purpose)

    render "billing_settings/payments/separate", locals: {
      target: target,
      trade_screening_needed: target.user?,
      manual_payment: manual_payment,
      purpose: purpose
    }
  end

  private

  sig { void }
  def ensure_positive_balance
    unless target.balance_in_cents.positive?
      flash[:error] = "No outstanding balance to pay"
      redirect_to :back
    end
  end

  sig { void }
  def ensure_target
    render_404 unless target!
  end

  sig { returns(User) }
  memoize def target
    T.must(target!)
  end

  sig { returns(T.nilable(User)) }
  def target!
    if params[:organization_id]
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless target.billable?
  end
end
