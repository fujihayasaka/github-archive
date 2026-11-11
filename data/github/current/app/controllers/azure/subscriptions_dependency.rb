# typed: strict
# frozen_string_literal: true

module Azure::SubscriptionsDependency
  include Billing::AzureOauthStateManagement
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Azure::BaseController }

  sig { void }
  def requires_azure_token
    flash[:error] = "Azure login expired. Please login again." unless azure_subscriptions_client.has_token?
  end

  sig { params(subscription_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def get_subscription(subscription_id:)
    azure_subscriptions_client.fetch_subscriptions.find do |subscription|
      subscription[:subscription_id] == subscription_id
    end
  end

  sig { returns(Billing::Azure::OrgSubscriptionClient) }
  def azure_subscriptions_client
    @azure_subscriptions_client ||= T.let(Billing::Azure::OrgSubscriptionClient.new(current_user, target), T.nilable(Billing::Azure::OrgSubscriptionClient))
  end

end
