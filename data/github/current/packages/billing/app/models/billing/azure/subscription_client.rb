# typed: strict
# frozen_string_literal: true

module Billing
  module Azure
    class SubscriptionClient

      class UnableToFetchAzureSubscriptionsError < StandardError; end

      class UnableToFetchAzureTenantsError < StandardError; end

      class UnableToFetchAzureSubscriptionPermissionsError < StandardError; end

      BASE_URI = "https://management.azure.com"
      API_VERSION = "2022-12-01"

      SUBSCRIPTION_DISABLED = "subscription has been disabled."

      SUBSCRIPTION_DOES_NOT_EXIST = "subscription does not exist."

      sig { params(http_client: GitHub::Azure::HttpClient).void }
      def initialize(http_client:)
        @http_client = http_client
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def tenants
        uri = "#{BASE_URI}/tenants?api-version=#{API_VERSION}"
        result = @http_client.send_request(method: :get, uri: uri)
        result.body[:value].map do |subscription|
          {
            tenant_id: subscription[:tenantId],
            tenant_category: subscription[:tenantCategory],
            display_name: subscription[:displayName],
            tenant_type: subscription[:tenantType]
          }
        end
      rescue Faraday::Error => e
        GitHub.logger.error("Failed to fetch Azure tenants", {
          exception: e,
          uri: uri,
          context: "Billing::Azure::SubscriptionClient#tenants"
        })
        raise UnableToFetchAzureTenantsError
      end

      # https://docs.microsoft.com/en-us/rest/api/resources/subscriptions/list
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def subscriptions
        uri = T.let("#{BASE_URI}/subscriptions?api-version=#{API_VERSION}", String)

        all_subscriptions = []
        loop do
          result = @http_client.send_request(method: :get, uri: uri)
          subscriptions = result.body[:value].map do |subscription|
            next unless subscription[:state].downcase == "enabled"
            { subscription_id: subscription[:subscriptionId], display_name: subscription[:displayName] }
          end.compact
          all_subscriptions.concat(subscriptions) if subscriptions.any?

          # Break the loop if no nextLink is available
          next_link = result.body[:nextLink]
          break unless next_link.present?
          uri = next_link
        end

        all_subscriptions
      rescue Faraday::Error => e
        GitHub.logger.error("Failed to fetch Azure subscriptions", {
          exception: e,
          uri: uri,
          context: "Billing::Azure::SubscriptionClient#subscriptions"
        })
        raise UnableToFetchAzureSubscriptionsError
      end

      # Calls the `GetSubscriptionState` API in Azure to
      # see if a subscription exists
      # https://docs.microsoft.com/en-us/rest/api/resources/subscriptions/get#subscriptionstate
      # Returns a hash of this format
      # {
      #  subscription_id: "subscription_id that was passed in",
      #  exists: "true if the subscription id exists, false otherwise.",
      #  reason: "reason for the subscription_id being invalid, does not exist or has been disabled.",
      # }
      sig { params(subscription_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def subscription_exists?(subscription_id:)
        # Return cached status if within TTL.
        status = get_cached_status(subscription_id)
        return status unless status.nil?

        uri = "#{BASE_URI}/subscriptions/#{subscription_id}?api-version=#{API_VERSION}"
        @http_client.send_request(method: :get, uri: uri)
        status = {
          subscription_id: subscription_id,
          exists: true
        }
      rescue Faraday::Error => client_error
        raise unless client_error.response
        case client_error.response[:status]
        when 404
          cached({
            exists: false,
            subscription_id: subscription_id,
            reason: SUBSCRIPTION_DOES_NOT_EXIST
          })
        when 401
          # Why does 401 mean that the subscription ID exists?
          # Currently, we're still onboarding a first party application in Azure
          # that should give us full access to the subscriptions service.
          # Until, then a 401 back from the service indicates that a subscription id "exists"
          # Note that this doesn't guard against subscription Ids that have been disabled.
          # This is a stop-gap measure so we don't accept random GUIDs as subscription-ids at the very least.
          cached({
            exists: true,
            subscription_id: subscription_id
          })
        else
          raise
        end
      end

      # https://learn.microsoft.com/en-us/rest/api/authorization/permissions/list-for-resource?view=rest-authorization-2022-04-01&tabs=HTTP
      sig { params(subscription_id: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def subscription_permissions(subscription_id:)
        uri = T.let("#{BASE_URI}/subscriptions/#{subscription_id}/providers/Microsoft.Authorization/permissions?api-version=2022-04-01", String)

        result = @http_client.send_request(method: :get, uri: uri)
        result.body[:value]
      rescue Faraday::Error => e
        GitHub.logger.error("Failed to fetch Azure subscription permissions", {
          exception: e,
          uri: uri,
          subscription_id: subscription_id,
          context: "Billing::Azure::SubscriptionClient#subscription_permissions"
        })
        raise UnableToFetchAzureSubscriptionPermissionsError
      end

      # The wildcard "*" means the user has all permissions, regardless of which condition/action is enabled or disabled.
      # The subscription owner role doesn't have "Microsoft.Subscription" conditions on `notActions`, unless specifically denied.
      # For more, see: https://learn.microsoft.com/en-us/azure/role-based-access-control/role-definitions
      sig { params(permissions: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
      def is_subscription_owner?(permissions:)
        return false if permissions.blank?
        return false unless permissions.is_a?(Array)
        # Steps for the validation:
        # 1. `permission[:actions]` is about an array of `actions`, for example `["*", "*/read"]`.
        #    In this case, include? will check the array for one occurrence of "*".
        # 2. `permission[:notActions].to_s` is about a string of `notActions`.
        #    For example `"[\"Microsoft.Subscription/cancel/action\", \"Microsoft.Subscription/enable/action\"]"`.
        #    In this case, exclude? will check the string for any occurrence of "Microsoft.Subscription".
        permissions.any? { |permission| permission[:actions]&.include?("*") && permission[:notActions].to_s.exclude?("Microsoft.Subscription") }
      end

      private

      sig { params(status: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def cached(status)
        Billing::Kv.store.set(subscription_cache_key(status[:subscription_id]), status.to_json, expires: 4.hours.from_now)
        status
      end

      sig { params(subscription_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_cached_status(subscription_id)
        val = Billing::Kv.store.get(subscription_cache_key(subscription_id)).value { nil }
        GitHub::JSON.load(val, failsafe: true).symbolize_keys unless val.nil?
      end

      sig { params(subscription_id: String).returns(String) }
      def subscription_cache_key(subscription_id)
        "azure.subscription_status[#{subscription_id}]"
      end
    end
  end
end
