# typed: strict
# frozen_string_literal: true

module Billing::AutoPayActions
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  # POST - create a disable reason (disables autopay)
  sig { void }
  def create
    ensure_billing_record_exists
    billable_account.disable_auto_pay! params[:auto_pay_reason].to_sym, actor: current_user
    flash[:notice] = "AutoPay has been disabled."
    redirect_to billing_information_path
  end

  # DELETE - remove a disable reason (enables autopay)
  sig { void }
  def destroy
    ensure_billing_record_exists
    billable_account.enable_auto_pay! params[:auto_pay_reason].to_sym, actor: current_user
    flash[:notice] = "AutoPay has been enabled."
    redirect_to billing_information_path
  end

  private

  sig { void }
  def ensure_billing_record_exists
    unless billable_account.has_billing_record?
      flash[:error] = "There's no payment record to update."
      redirect_back(fallback_location: billing_information_path)
    end
  end

  # Subclasses must implement this method to return the User or Business
  sig { returns(T.untyped) }
  def billable_account
    T.unsafe(nil)
  end

  # Subclasses must implement this method to return the redirect path
  sig { returns(String) }
  def billing_information_path
    T.unsafe(nil)
  end
end
