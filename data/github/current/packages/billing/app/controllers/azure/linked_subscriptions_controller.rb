# typed: strict
# frozen_string_literal: true

class Azure::LinkedSubscriptionsController < Azure::BaseController
  before_action :requires_azure_token, only: %i[update]

  sig { void }
  def update
    is_updating = !customer&.azure_subscription_id.to_s.empty?
    if is_updating
      GitHub.dogstats.increment("azure.organizations.edit_subscription_id")
    else
      GitHub.dogstats.increment("azure.organizations.set_subscription_id")
    end

    selected_subscription = get_subscription(subscription_id: params[:selected_subscription_id])
    subscription_selection_confirmation = params[:confirm_subscription_selection]

    if selected_subscription.nil?
      flash[:error] = "Invalid subscription specified"
    elsif subscription_selection_confirmation.to_i == 0
      flash[:error] = "You must confirm the subscription selection before proceeding"
    elsif T.must(customer).update(
          azure_subscription_id: selected_subscription[:subscription_id],
          azure_subscription_name: selected_subscription[:display_name],
          metered_via_azure: true
        )
      target.instrument("azure_organization_user_self_updated_subscription_id", actor: current_user)
      success_add = "You have successfully added an Azure subscription to your payment information."
      success_update = "You have successfully updated your Azure subscription."
      flash[:notice] = is_updating ? success_update : success_add

      Billing::Kv.store.del(T.must(customer).invalid_azure_subscription_id_key)
    else
      failure_add = "There was an issue adding an Azure subscription to your payment information."
      failure_update = "There was an updating your current Azure subscription."
      flash[:error] = is_updating ? failure_update : failure_add
    end

    redirect_to org_billing_settings_path
  end

  sig { void }
  def destroy
    unless T.must(customer).can_disable_metered_via_azure?
      GitHub.dogstats.increment("azure.organizations.delete_subscription_id_attempt")
      flash[:error] = "Azure subscription cannot be removed until your next metered cycle on #{target.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}."
      redirect_back(fallback_location: org_billing_settings_url)
      return
    end

    GitHub.dogstats.increment("azure.organizations.delete_subscription_id")
    if T.must(customer).update(azure_subscription_id: nil, azure_subscription_name: nil)
      flash[:notice] = "Azure subscription was successfully removed."
    else
      flash[:error] = "There was an issue removing the Azure subscription from your payment information."
    end

    redirect_back(fallback_location: org_billing_settings_url)
  end

  private

  sig { returns(T.nilable(Customer)) }
  def customer
    return unless target

    @customer ||= T.let(
      begin
        customer = target.customer

        return customer if customer

        Billing::CreateCustomer.perform(target).customer
      end, T.nilable(Customer))
  end
end
