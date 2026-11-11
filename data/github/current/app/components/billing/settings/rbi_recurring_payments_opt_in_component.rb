# typed: strict
# frozen_string_literal: true

class Billing::Settings::RBIRecurringPaymentsOptInComponent < ApplicationComponent
  sig { params(account: Billing::Types::Account, opt_in_path: String, rbi_opt_in_param: T::Boolean).void }
  def initialize(account:, opt_in_path:, rbi_opt_in_param: false)
    @account = account
    @opt_in_path = opt_in_path
    @rbi_opt_in_param = rbi_opt_in_param
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :account

  sig { returns(String) }
  attr_reader :opt_in_path

  sig { returns(T::Boolean) }
  attr_reader :rbi_opt_in_param

  sig { returns(T::Boolean) }
  def render?
    eligible_for_opt_in? || opted_in_pending_card_update?
  end

  sig { returns(T::Boolean) }
  def eligible_for_opt_in?
    return false unless account.user?
    return false unless rbi_opt_in_param

    BillingSettings::RBIRecurringPaymentsController::ELIGIBLE_USER_IDS.include?(account.id) &&
      !FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, account, default: false) &&
      account.autopay_disabled_by_india_rbi?
  end

  sig { returns(T::Boolean) }
  def opted_in_pending_card_update?
    return false unless account.user?
    return false unless BillingSettings::RBIRecurringPaymentsController::ELIGIBLE_USER_IDS.include?(account.id)
    return false unless FeatureFlag.vexi.enabled?(:billing_india_rbi_recurring_payments, account, default: false)
    return false unless account.autopay_disabled_by_india_rbi?
    return false if account.manual_dunning_period.present?

    true
  end
end
