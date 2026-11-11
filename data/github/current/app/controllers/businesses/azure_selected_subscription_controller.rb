# typed: strict
# frozen_string_literal: true

class Businesses::AzureSelectedSubscriptionController < Businesses::BusinessController
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

    begin
      selected_subscription = get_subscription(subscription_id: params[:selected_subscription_id])
    rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError
      flash[:error] = "Failed to fetch subscriptions. Please try again later or contact support."
      redirect_to enterprise_billing_payment_information_path(this_business)
      return
    end

    subscription_selection_confirmation = params[:confirm_subscription_selection]

    if selected_subscription.nil?
      flash[:error] = "Invalid subscription specified"
    elsif selected_subscription.has_key?(:billable) && !selected_subscription[:billable] &&
          selected_subscription[:subscription_id] != this_business.customer&.azure_subscription_id
      flash[:error] = "This subscription type is not supported"
    else
      begin
        permissions = azure_subscriptions_client.subscription_permissions(subscription_id: selected_subscription[:subscription_id])
        is_subscription_owner = azure_subscriptions_client.is_subscription_owner?(permissions: permissions)
        unless is_subscription_owner
          subscription_permissions_error = "You don't have permission to connect this subscription. Please select an Azure subscription with owner permission."
        end
      rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionPermissionsError
        subscription_permissions_error = "Failed to verify subscription permissions. Please try again."
      end

      if subscription_selection_confirmation.to_i == 0
        flash[:error] = "You must confirm the subscription selection before proceeding"
      elsif !is_subscription_owner
        flash[:error] = subscription_permissions_error
      elsif this_business.customer.update(
            azure_subscription_id: selected_subscription[:subscription_id],
            azure_subscription_name: selected_subscription[:display_name],
            metered_via_azure: true
          )
        this_business.instrument("azure_self_serve_user_self_updated_subscription_id", actor: current_user)
        if this_business.customer.azure_subscription_blocklisted?
          flash[:error] = "This account has been flagged. Please visit https://support.github.com for further information."
        else
          # Remove CC or PayPal payment information for GHE metered EAs, if set
          if this_business.metered_ghe?
            this_business.customer.payment_method.clear_payment_details(current_user) if this_business.customer.payment_method.present?
          end

          Billing::AuthAndCapture::AuthorizeTrialJob.perform_later(this_business, current_user) if this_business.trial?
          success_add = "You have successfully added an Azure subscription to your payment information."
          success_update = "You have successfully updated your Azure subscription."
          flash[:notice] = is_updating ? success_update : success_add
        end
      else
        failure_add = "There was an issue adding an Azure subscription to your payment information."
        failure_update = "There was an issue updating your current Azure subscription."
        flash[:error] = is_updating ? failure_update : failure_add
      end
    end

    # If this business is a metered trial, the only way to add an Azure Subscription is from the
    # Payment information page. Since the user could have initiated adding the subscription from
    # the Copilot Business page or from the Activate GitHub Enterprise page, we need to redirect
    # them back to the right page to finish the process.
    if this_business.metered_ghec_trial?
      if should_return_to_trial_activations?
        redirect_to enterprise_trial_activations_path(this_business)
      else
        redirect_to settings_billing_activations_enterprise_path(this_business)
      end

      return
    end
    redirect_to enterprise_billing_payment_information_path(this_business)
  end

  sig { void }
  def destroy
    unless this_business.customer&.can_disable_metered_via_azure?
      GitHub.dogstats.increment("azure.businesses.delete_subscription_id_attempt")
      flash[:error] = "Azure subscription cannot be removed until your next metered cycle on #{this_business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}."
      redirect_back(fallback_location: enterprise_billing_path(this_business))
      return
    end

    GitHub.dogstats.increment("azure.self_serve.delete_subscription_id")
    if this_business.customer.update(azure_subscription_id: nil, azure_subscription_name: nil)
      flash[:notice] = "Azure subscription was successfully removed."
    else
      flash[:error] = "There was an issue removing the Azure subscription from your payment information."
    end

    redirect_back(fallback_location: enterprise_billing_path(this_business))
  end

  private

  sig { params(subscription_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def get_subscription(subscription_id:)
    azure_subscriptions_client.fetch_subscriptions.find do |subscription|
      subscription[:subscription_id] == subscription_id
    end
  end

  sig { returns(T::Boolean) }
  def should_return_to_trial_activations?
    return false unless this_business.dfd_trial?
    return false if this_business.copilot_trial_activation_blocked?
    session[:return_to] == enterprise_trial_activations_path(this_business)
  end
end
