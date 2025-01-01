# typed: strict
# frozen_string_literal: true

class Azure::SettingsController < Azure::BaseController
  extend T::Sig

  sig { void }
  def update
    return render_404 if target.delegate_billing_to_business?

    unless target.organization?
      flash[:error] = "Cannot update metered via Azure on a non-organization"
      redirect_to :back
      return
    end

    if params[:metered_via_azure] == "false" && !target.customer&.can_disable_metered_via_azure?
      GitHub.dogstats.increment("azure.organizations.disable_subscription_id_attempt")
      flash[:error] = "Azure subscription cannot be disabled until your next metered cycle on #{target.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}."
      redirect_to :back
      return
    end

    if params[:metered_via_azure] == "true" && target.customer&.metered_via_azure_key.present?
      Billing::Kv.store.set(target.customer.metered_via_azure_key, Time.now.to_s, expires: target.next_metered_billing_cycle_starts_at)
    end

    if !target.customer
      flash[:error] = "Unable to update metered via Azure on an organization without a customer"
    else
      customer = target.customer
      customer.metered_via_azure = params[:metered_via_azure] || false
      if customer.save
        flash[:notice] = "Metered billing via Azure successfully updated"
      else
        flash[:error] = "There was an error during the update of metered billing via Azure"
      end
    end

    redirect_to :back
  end
end
