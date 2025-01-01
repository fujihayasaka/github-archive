# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::AuthorizationsController < StafftoolsController
  sig { void }
  def create
    entity = find_entity
    customer = entity&.customer
    return redirect_to :back, flash: { error: "Customer not found" } if entity.nil? || customer.nil?

    last_auth = Billing::BillingTransaction.current_authorizations_for_customer(customer.id).last
    if last_auth.nil? || !last_auth.failed?
      return redirect_to :back, notice: "A failed authorization is required to retry"
    end

    if FeatureFlag.vexi.enabled?(:billing_payment_authorization_domain_interface, entity, default: false)
      Billing.domain.payment_authorizations.create(
        customer_id: customer.id,
        amount_in_cents: last_auth.amount_in_cents,
        origin: "Stafftools::Billing::AuthorizationsController",
        check_overage: false,
        check_payment_method: false,
        check_trust_tier: false,
        unlock_billing_on_success: true,
        reset_billing_attempts_when_unlocked: false,
      )
    else
      Billing::CreateAuthorizationBillingTransactionJob.perform_later(
        entity_id: entity.id,
        amount_in_cents: last_auth.amount_in_cents,
        is_business: entity.is_a?(::Business),
        unlock_billing_on_success: true,
        reset_billing_attempts_when_unlocked: false,
        origin: "Stafftools::Billing::AuthorizationsController",
      )
    end

    redirect_to :back, notice: "Authorization triggered. You may need to refresh the page."
  end

  private

  sig { returns(T.nilable(Billing::Types::Account)) }
  def find_entity
    if params[:user_id].present?
      User.includes(:customer).find_by(id: params[:user_id])
    elsif params[:business_id].present?
      Business.includes(:customer).find_by(id: params[:business_id])
    end
  end
end
