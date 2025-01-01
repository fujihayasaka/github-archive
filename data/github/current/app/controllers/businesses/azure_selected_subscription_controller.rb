# typed: strict
# frozen_string_literal: true

class Businesses::AzureSelectedSubscriptionController < Businesses::BusinessController
  extend T::Sig

  include Businesses::AzureSubscriptions

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :requires_azure_token, only: %i[update]
  before_action only: [:update] do
    T.bind(self, Businesses::AzureSelectedSubscriptionController)

    check_trade_compliance(target: this_business, sdn_redirect: true)
  end

  sig { void }
  def update
    is_updating = !this_business.customer&.azure_subscription_id.to_s.empty?
    if is_updating
      GitHub.dogstats.increment("azure.self_serve.edit_subscription_id")
    else
      GitHub.dogstats.increment("azure.self_serve.set_subscription_id")
    end

    selected_subscription = get_subscription(subscription_id: params[:selected_subscription_id])
    subscription_selection_confirmation = params[:confirm_subscription_selection]

    if selected_subscription.nil?
      flash[:error] = "Invalid subscription specified"
    elsif subscription_selection_confirmation.to_i == 0
      flash[:error] = "You must confirm the subscription selection before proceeding"
    elsif this_business.customer.update(
          azure_subscription_id: selected_subscription[:subscription_id],
          azure_subscription_name: selected_subscription[:display_name],
          metered_via_azure: true
        )
      this_business.instrument("azure_self_serve_user_self_updated_subscription_id", actor: current_user)
      # Remove CC or PayPal payment information for GHE metered EAs, if set
      if this_business.metered_ghe? && this_business.feature_enabled?(:metered_ghe_cc_paypal_payments)
        this_business.customer.payment_method.clear_payment_details(current_user) if this_business.customer.payment_method.present?
      end

      success_add = "You have successfully added an Azure subscription to your payment information."
      success_update = "You have successfully updated your Azure subscription."
      flash[:notice] = is_updating ? success_update : success_add
    else
      failure_add = "There was an issue adding an Azure subscription to your payment information."
      failure_update = "There was an updating your current Azure subscription."
      flash[:error] = is_updating ? failure_update : failure_add
    end

    # If this business is a metered trial, the only way to add an azure subscription is from the activation page.
    # User should be redirected back to the activation page to finish the process.
    if this_business.metered_ghec_trial?
      redirect_to settings_billing_activations_enterprise_path(this_business)
      return
    end
    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_payment_information_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(
                    this_business,
                    tab: :payment_information,
                    show_subscriptions: false
                  )
    end
  end

  sig { void }
  def destroy
    unless this_business.customer&.can_disable_metered_via_azure?
      GitHub.dogstats.increment("azure.businesses.delete_subscription_id_attempt")
      flash[:error] = "Azure subscription cannot be removed until your next metered cycle on #{this_business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}."
      fallback_location = if this_business.billed_via_billing_platform?
        enterprise_billing_path(this_business)
      else
        settings_billing_enterprise_url(this_business)
      end
      redirect_back(fallback_location: fallback_location)
      return
    end

    GitHub.dogstats.increment("azure.self_serve.delete_subscription_id")
    if this_business.customer.update(azure_subscription_id: nil, azure_subscription_name: nil)
      flash[:notice] = "Azure subscription was successfully removed."
    else
      flash[:error] = "There was an issue removing the Azure subscription from your payment information."
    end

    fallback_location = if this_business.billed_via_billing_platform?
      enterprise_billing_path(this_business)
    else
      settings_billing_enterprise_url(this_business)
    end

    redirect_back(fallback_location: fallback_location)
  end

  private

  sig { params(subscription_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def get_subscription(subscription_id:)
    azure_subscriptions_client.fetch_subscriptions.find do |subscription|
      subscription[:subscription_id] == subscription_id
    end
  end
end
