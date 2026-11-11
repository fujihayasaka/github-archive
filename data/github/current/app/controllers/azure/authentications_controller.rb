# typed: strict
# frozen_string_literal: true

class Azure::AuthenticationsController < Azure::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  sig { void }
  def show
    if params[:azure_state].blank?
      flash[:error] = "Missing state from Azure"
      return redirect_to org_billing_settings_path
    end

    @azure_state = T.let(state_to_hash(state: params[:azure_state]), T.nilable(T::Hash[Symbol, T.untyped]))
    return redirect_to org_billing_settings_path if @azure_state.nil?

    code = @azure_state[:oauth_code]
    explicit_tenant_selected = @azure_state[:explicit_tenant_selected] == true

    return redirect_to org_billing_settings_path if code.nil?

    client = Billing::Azure::OrgSubscriptionClient.new(current_user, target)
    client.fetch_and_store_token(code)

    tenants = client.fetch_tenants

    if !explicit_tenant_selected && !tenants.nil? && tenants.count > 1
      GitHub.dogstats.increment("azure.organizations.showing_tenant_selection")

      # Ask user to select a tenant first
      return redirect_to org_billing_settings_path(anchor: "open_tenant_dialog")
    end

    GitHub.dogstats.increment("azure.organizations.showing_subscription_selection")

    # Only one tenant? Then fetch subscriptions from there
    redirect_to org_billing_settings_path(anchor: "open_dialog")
  rescue JSON::JSONError
    flash[:error] = "Failed decoding state from Azure"
    redirect_to org_billing_settings_path
  rescue Billing::AzureOauthStateManagement::AzureStateValidationError => e
    flash[:error] = "Authentication request invalid or expired. Please try again."
    redirect_to org_billing_settings_path
  rescue Faraday::Error => e
    Failbot.report(e, client_response: e.response)
    flash[:error] = "Failed to fetch authentication information from Azure. Please try again."
    redirect_to org_billing_settings_path
  end
end
