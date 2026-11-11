# typed: true
# frozen_string_literal: true

class Businesses::AzureSubscriptionsController < Businesses::BusinessController
  include Businesses::AzureSubscriptions

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :requires_azure_token, only: %i[index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    subscriptions = azure_subscriptions_client.fetch_subscriptions

    current_subscription = subscriptions.find do |subscription|
      subscription[:subscription_id].eql?(this_business.customer&.azure_subscription_id)
    end

    current_subscription[:selected] = true if current_subscription.present?

    should_validate_permissions = this_business.feature_flag_enabled_or_raise?(:validate_azure_subscription_permissions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    render "businesses/azure_subscriptions/index",
           layout: false,
           locals: { subscriptions: subscriptions, fetch_failed: false, should_validate_permissions: should_validate_permissions }
  rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError
    render "businesses/azure_subscriptions/index", layout: false, locals: { subscriptions: [], fetch_failed: true, should_validate_permissions: false }
  end
end
