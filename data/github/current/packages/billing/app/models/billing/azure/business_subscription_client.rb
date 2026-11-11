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

      # In development, skip the OAuth code exchange entirely and store a pre-fetched
      # ARM access token (e.g. from `az account get-access-token`). Kubernetes workload
      # identity is unavailable outside a pod, and client_secret may not be configured.
      if Rails.env.development? && ENV["BILLING_AZURE_DEV_TOKEN"].present?
        ActiveRecord::Base.connected_to(role: :writing) { Billing::Kv.store.set(keyvault_key, ENV["BILLING_AZURE_DEV_TOKEN"], expires: 1.hour.from_now) }
        return
      end

      if use_oidc?
        begin
          token_client =
            GitHub::Azure::AadCodeGrantTokenClient.new(
              client_id: GitHub.azure_oauth_app_id,
              tenant_id: GitHub.azure_oauth_app_tenant_id,
              tenant_path: "organizations",
              scope: "https://management.core.windows.net/.default",
              code: code,
              redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses
            )

          token = token_client.fetch_token
          ActiveRecord::Base.connected_to(role: :writing) { Billing::Kv.store.set(keyvault_key, token, expires: 1.hour.from_now) }
          GitHub.dogstats.increment("billing.azure.subscription.oidc_token", tags: ["result:success", "entity:business"])
        rescue GitHub::Azure::OIDCTokenProvider::TokenAcquisitionError, Faraday::Error => e
          GitHub.dogstats.increment("billing.azure.subscription.oidc_token", tags: ["result:failure", "entity:business"])
          GitHub.logger.error("billing.azure.business_subscription.oidc.token_acquisition_failed", "gh.user.id" => @current_user.id, "gh.business.id" => @this_business.id, "gh.error" => e.message)
          raise
        end
      else
        token_client =
          GitHub::Azure::AadCodeGrantTokenClient.new(
            client_id: GitHub.azure_oauth_app_id,
            client_secret: GitHub.azure_oauth_app_secret,
            scope: "https://management.core.windows.net/.default",
            code: code,
            redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses
          )

        token = token_client.fetch_token
        ActiveRecord::Base.connected_to(role: :writing) { Billing::Kv.store.set(keyvault_key, token, expires: 1.hour.from_now) }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def fetch_tenants
      subscription_client.tenants
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def fetch_subscriptions
      if @this_business.feature_flag_enabled?(:billing_show_unsupported_azure_subscriptions, default: false)
        subscription_client.subscriptions.map do |subscription|
          subscription.merge(
            billable: Billing::Azure::SubscriptionFilter.billable_subscription?(subscription, billable_entity: @this_business)
          )
        end
      else
        subscription_client.subscriptions.select do |subscription|
          Billing::Azure::SubscriptionFilter.billable_subscription?(subscription, billable_entity: @this_business)
        end
      end
    end

    sig { params(subscription_id: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def subscription_permissions(subscription_id:)
      subscription_client.subscription_permissions(subscription_id: subscription_id)
    end

    sig { params(permissions: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
    def is_subscription_owner?(permissions:)
      subscription_client.is_subscription_owner?(permissions: permissions)
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

    sig { returns(T::Boolean) }
    def use_oidc?
      FeatureFlag.vexi.enabled?(:billing_subscription_check_oidc, @current_user, default: false)
    end

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
