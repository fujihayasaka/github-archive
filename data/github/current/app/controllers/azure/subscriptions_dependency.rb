# typed: strict
# frozen_string_literal: true

module Azure::SubscriptionsDependency
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

  sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(String) }
  def hash_to_state(hash:)
    Base64.encode64(hash.to_json)
  end

  sig { params(state: String).returns(T::Hash[Symbol, T.untyped]) }
  def state_to_hash(state:)
    decoded_state = Base64.decode64(state)
    JSON.parse(decoded_state, { symbolize_names: true })
  end
end
