# typed: strict
# frozen_string_literal: true

class Billing::RetryPaymentsController < ApplicationController
  before_action :ensure_billing_enabled,
    :login_required,
    :ensure_has_permission_to_retry_payment

  sig { void }
  def create
    customer_to_retry_payment = T.must(customer)
    if can_retry_payment?
      Billing::RetryFailedPaymentJob.perform_later(customer_to_retry_payment)
    end

    redirect_to :back
  end

  private

  sig { returns(Billing::Types::Account) }
  def resource_for_conditional_access
    customer&.billable_owner || current_user
  end

  sig { returns(T::Boolean) }
  def can_retry_payment?
    customer_to_retry_payment = T.must(customer)
    return false if Billing::RetryFailedPaymentJob.currently_retrying?(customer_to_retry_payment)
    return false if customer_to_retry_payment.payment_method_verification_in_progress?
    true
  end

  sig { returns(T.nilable(Customer)) }
  memoize def customer
    return nil unless customer_id = params[:customer_id]
    Customer.find(customer_id)
  end

  sig { void }
  def ensure_has_permission_to_retry_payment
    can_retry_payment = false
    billable_owner = customer&.billable_owner
    if billable_owner&.is_a?(Business) || billable_owner&.is_a?(Organization)
      can_retry_payment = billable_owner.adminable_by?(current_user) || T.unsafe(billable_owner).billing_manager?(current_user)
    elsif billable_owner.present?
      can_retry_payment = billable_owner.adminable_by?(current_user)
    end
    render_404 unless can_retry_payment
  end
end
