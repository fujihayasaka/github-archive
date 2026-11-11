# typed: true
# frozen_string_literal: true

class Businesses::AzureTenantsController < Businesses::BusinessController
  include Businesses::AzureSubscriptions

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :requires_azure_token, only: %i[index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    tenants = azure_subscriptions_client.fetch_tenants

    render "businesses/azure_tenants/index",
           layout: false,
           locals: { tenants: tenants, fetch_failed: false, business: this_business }
  rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError
    render "businesses/azure_tenants/index",
           layout: false,
           locals: { tenants: [], fetch_failed: true, business: this_business }
  end
end
