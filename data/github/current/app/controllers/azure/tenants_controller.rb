# typed: strict
# frozen_string_literal: true

class Azure::TenantsController < Azure::BaseController
  before_action :requires_azure_token, only: %i[index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:index]

  sig { void }
  def index
    tenants = azure_subscriptions_client.fetch_tenants
    render Azure::TenantSelectionDialogComponent.new(target, tenants, false), layout: false
  rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError
    render Azure::TenantSelectionDialogComponent.new(target, [], true), layout: false
  end
end
