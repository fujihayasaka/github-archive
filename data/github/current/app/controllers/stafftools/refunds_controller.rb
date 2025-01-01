# typed: true
# frozen_string_literal: true

class Stafftools::RefundsController < StafftoolsController
  include Stafftools::TradeCompliance::SharedControllerMethods

  before_action :ensure_billing_enabled
  before_action :ensure_transaction_exists
  before_action :ensure_target
  before_action :ensure_not_restricted

  def create
    ::Billing::ReverseTransactionJob.perform_later(transaction)
    flash[:notice] = "Transaction reversal has been queued up and will process in the background."

    redirect_back_with_fallback
  end

  private

  def redirect_back_with_fallback
    redirect_back(fallback_location: fallback_location)
  end

  def fallback_location
    stafftools_billing_transaction_path(transaction_id: params[:transaction_id])
  end

  memoize def target
    transaction.billable_entity
  end

  memoize def transaction
    ::Billing::BillingTransaction.find_by(transaction_id: params[:transaction_id])
  end

  def ensure_transaction_exists
    return if transaction.present?

    flash[:error] = "Transaction not found."
    redirect_back_with_fallback
  end

  def ensure_target
    return if target.present?

    flash[:error] = "Target not found."
    redirect_back_with_fallback
  end

  def ensure_not_restricted
    ensure_target_not_restricted(feature_type: :refund_eligible, fallback_location: fallback_location)
  end
end
