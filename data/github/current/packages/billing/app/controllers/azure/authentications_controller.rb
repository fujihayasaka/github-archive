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
    code = params[:oauth_code]

    # This is true if we already sent the user to explicitly select a tenant
    explicit_tenant_selected = params[:explicit_tenant_selected] == "true"

    redirect_to settings_org_billing_path(target) if code.nil?

    if code
      client = Billing::Azure::OrgSubscriptionClient.new(current_user, target)
      client.fetch_and_store_token(code)

      tenants = client.fetch_tenants

      if !explicit_tenant_selected && !tenants.nil? && tenants.count > 1
        GitHub.dogstats.increment("azure.organizations.showing_tenant_selection")

        # Ask user to select a tenant first
        redirect_to settings_org_billing_path(target, anchor: "open_tenant_dialog")
      else
        GitHub.dogstats.increment("azure.organizations.showing_subscription_selection")

        # Only one tenant? Then fetch subscriptions from there
        redirect_to settings_org_billing_path(target, anchor: "open_dialog")
      end
    end
  rescue Faraday::Error => e
    Failbot.report(e, client_response: e.response)
    flash[:error] = "Failed to fetch authentication information from Azure. Please try again."
    redirect_to settings_org_billing_path(target)
  end
end
