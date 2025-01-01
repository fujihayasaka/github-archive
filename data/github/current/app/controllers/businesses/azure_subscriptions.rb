# typed: strict
# frozen_string_literal: true

module Businesses::AzureSubscriptions
  extend T::Helpers

  sig { void }
  def requires_azure_token
    T.unsafe(self).flash[:error] = "Azure login expired. Please login again." unless azure_subscriptions_client.has_token?
  end

  sig { returns(Billing::Azure::BusinessSubscriptionClient) }
  def azure_subscriptions_client
    this_business = T.unsafe(self).this_business
    current_user = T.unsafe(self).current_user
    @azure_subscriptions_client ||= T.let(Billing::Azure::BusinessSubscriptionClient.new(current_user, this_business), T.nilable(Billing::Azure::BusinessSubscriptionClient))
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
