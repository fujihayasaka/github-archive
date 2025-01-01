# typed: true
# frozen_string_literal: true

module Mobile
  module Google
    # Service for calling Google Play Store API. It leverages `PlayStoreClient` to make the actual API calls. It handles
    # the logic for iterating over all known app ids, if Play Store returns a purchase token mismatch error.
    class PlayStoreService
      extend T::Sig

      sig { returns(PlayStoreService) }
      def self.from_config
        service_account_key = GitHub.google_iap_service_account_key

        new(service_account_key:)
      end

      def initialize(service_account_key:)
        @play_store_client = PlayStoreClient.new(service_account_key: service_account_key)
      end

      class PlayStoreAppId < T::Enum
        extend T::Sig

        enums do
          Production = new
          Staff = new
          Dev = new
        end

        def app_id
          case self
          when Production then PRODUCTION_APP_ID
          when Staff then STAFF_APP_ID
          when Dev then DEVELOPMENT_APP_ID
          end
        end
      end

      class BaseException < StandardError; end
      class BadRequestException < BaseException; end
      class PurchaseNotFoundError < BadRequestException; end

      # Main entry point for getting the subscription summary for a purchase token. This method depends on
      #
      sig { params(purchase_token: String, product_id: String).returns(SubscriptionPurchaseSummary) }
      def get_subscription_purchase_summary(purchase_token:, product_id:)
        subscription_purchase = get_subscription_purchase(purchase_token:, product_id:)

        SubscriptionPurchaseSummary.from_subscription_purchase(subscription_purchase, purchase_token)
      end

      # Main entry point for getting the subscription purchase for a purchase token and the product id. The method
      # depends on the PlayStoreClient#get_subscription_purchase_for_product_id method to make the actual API call.

      # Furthermore, this method iterates over all known app ids to find the subscription purchase. If the purchase token
      # can't be matched with any of our apps, then we will conclude that the purchase is not valid and return purchase token not found error.
      #
      # Note: This method calls PlayStoreClient#get_subscription_purchase_for_product_id method, which can raise
      # PlayStoreClient::PurchaseTokenMismatchException and PlayStoreClient::PurchaseNotFoundError exceptions.
      sig { params(purchase_token: String, product_id: String).returns(::Google::Apis::AndroidpublisherV3::SubscriptionPurchase) }
      def get_subscription_purchase(purchase_token:, product_id:)
        app_ids = [
          PlayStoreAppId::Production.app_id,
          PlayStoreAppId::Staff.app_id,
          PlayStoreAppId::Dev.app_id
        ]

        app_ids.each do |app_id|
          begin
            return play_store_client.fetch_subscription_purchase_for_product_id(purchase_token: purchase_token, package_name: app_id, product_id: product_id)
          rescue PlayStoreClient::PurchaseTokenMismatchException
            next
          end
        end

        # If the purchase token can't be matched with any of our apps, then we will conclude that the purchase is not valid and return purchase token not found error.
        raise PurchaseNotFoundError.new
      end

      private

      attr_reader :play_store_client
    end
  end
end
