# typed: strict
# frozen_string_literal: true

class Azure::SubscriptionsController < Azure::BaseController
  before_action :requires_azure_token, only: %i[index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  sig { void }
  def index
    subscriptions = azure_subscriptions_client.fetch_subscriptions

    current_subscription = subscriptions.find do |subscription|
      subscription[:subscription_id].eql?(target.customer&.azure_subscription_id)
    end

    current_subscription[:selected] = true if current_subscription.present?

    render Azure::SubscriptionSelectionDialogComponent.new(target, subscriptions, false), layout: false
  rescue Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError
    render Azure::SubscriptionSelectionDialogComponent.new(target, [], true), layout: false
  end
end
