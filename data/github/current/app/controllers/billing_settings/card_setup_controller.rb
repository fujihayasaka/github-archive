# typed: strict
# frozen_string_literal: true

class BillingSettings::CardSetupController < ApplicationController
  include Businesses::Concerns::BusinessLayoutClusterDependencies

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_feature_flag
  before_action :ensure_target_is_billable
  before_action only: [:new] do
    T.bind(self, BillingSettings::CardSetupController)

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
    only: [:new, :check]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :check], optional: true

  sig { void }
  def check # rubocop:todo GitHub/UseRestfulActions
    return head 404 if !request.xhr? || params[:payment_id].blank?

    if target.billing_transactions.exists?(platform_transaction_id: params[:payment_id])
      Billing::EnableAutoPayAfterCardSetupJob.perform_later(T.must(target.customer).id, params[:payment_id])
      head 200
    else
      head 202
    end
  end

  sig { void }
  def new
    if !target.autopay_disabled_by_india_rbi?
      flash[:error] = "Recurring card setup is not available for this account"
      return redirect_to helpers.target_billing_url(target)
    end

    purpose = params[:purpose]&.to_sym
    manual_payment = Billing::ManualPayment.new(target: target, purpose: purpose)

    render "billing_settings/card_setup/new", locals: {
      target: target,
      trade_screening_needed: target.user?,
      manual_payment: manual_payment,
    }
  end

  private

  sig { void }
  def ensure_feature_flag
    render_404 unless FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, target, default: false)
  end

  sig { void }
  def ensure_positive_balance
    unless target.balance_in_cents.positive?
      flash[:error] = "No outstanding balance to pay"
      redirect_back(fallback_location: helpers.target_billing_url(target))
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
      org = Organization.find_by_login(params[:organization_id])
      if org && (org.direct_or_team_member?(current_user) || org.billing_manager?(current_user)) && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    t = target!
    t.is_a?(Organization) ? t : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless target.billable?
  end
end
