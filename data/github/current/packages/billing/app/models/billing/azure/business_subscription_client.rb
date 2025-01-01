# typed: strict
# frozen_string_literal: true

module Billing::Azure
  class BusinessSubscriptionClient

    sig { params(current_user: User, this_business: Business).void }
    def initialize(current_user, this_business)
      @current_user = current_user
      @this_business = this_business
    end

    sig { params(code: String).returns(T.untyped) }
    def fetch_and_store_token(code)
      keyvault_key = keyvault_key(@current_user, @this_business)

      token_client =
        GitHub::Azure::AadCodeGrantTokenClient.new(
          client_id: GitHub.azure_oauth_app_id,
          client_secret: GitHub.azure_oauth_app_secret,
          grant_type: "authorization_code",
          scope: "https://management.core.windows.net/.default",
          code: code,
          redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses
        )

      token = token_client.fetch_token
      ActiveRecord::Base.connected_to(role: :writing) { Billing::Kv.store.set(keyvault_key, token, expires: 1.hour.from_now) }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def fetch_tenants
      subscription_client.tenants
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def fetch_subscriptions
      subscription_client.subscriptions
    end

    sig { returns(T::Boolean) }
    def has_token?
      !token_from_keyvault.empty?
    end

    sig { returns(String) }
    def token_from_keyvault
      keyvault_key = keyvault_key(@current_user, @this_business)

      # Even tho we only read here, it is important to read this using the same role we used to write (in this case the primary database).
      # In some rare cases the secondary database might not have been updated at the moment we try to read this.
      ActiveRecord::Base.connected_to(role: :writing) { return Billing::Kv.store.get(keyvault_key).value { nil } || "" }
    end

    private

    sig { returns(Billing::Azure::SubscriptionClient) }
    def subscription_client
      token = token_from_keyvault
      token_client = GitHub::Azure::ConstantTokenClient.new(token: token)
      http_client = GitHub::Azure::HttpClient.new(token_client: token_client)
      Billing::Azure::SubscriptionClient.new(http_client: http_client)
    end

    sig { params(user: User, business: Business).returns(String) }
    def keyvault_key(user, business)
      "azure_oauth_token_#{user.id}_#{business.id}"
    end
  end
end
