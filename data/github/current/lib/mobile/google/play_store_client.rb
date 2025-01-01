# typed: true
# frozen_string_literal: true

require "google/apis/androidpublisher_v3"
require "googleauth"
require "json"

module Mobile
  module Google

    # Client for the Play Store Developer API
    class PlayStoreClient

      def initialize(service_account_key:)
        @service = ::Google::Apis::AndroidpublisherV3::AndroidPublisherService.new.tap do |service|
          service.authorization = ::Google::Auth::DefaultCredentials.make_creds(
            scope: ANDROID_PUBLISHER_SCOPE,
            json_key_io: StringIO.new(service_account_key)
          )
        end
      end

      class BaseException < StandardError; end
      class PurchaseTokenMismatchException < BaseException; end

      attr_reader :service

      # https://googleapis.dev/ruby/google-api-client/v0.53.0/Google/Apis/AndroidpublisherV3/AndroidPublisherService.html#get_purchase_subscription-instance_method
      sig { params(purchase_token: String, package_name: String, product_id: String).returns(::Google::Apis::AndroidpublisherV3::SubscriptionPurchase) }
      def fetch_subscription_purchase_for_product_id(purchase_token:, package_name:, product_id:)
        response = service.get_purchase_subscription(package_name, product_id, purchase_token)
      rescue ::Google::Apis::Error => e
        # Google will return us a 400 with a specific error message if the purchase token does not match the package name in order to avoid fradualent activity,
        # since the purchase token of a different app can still be a valid purchase token on the Play Store. The API will return a success response only when:
        # - The purchase token is valid
        # - The purchase token belongs to the provided package name
        # In our case we want to verify the purchase token by trying all GitHub Android apps known to us with the following order:
        # Production -> Staff -> Test
        # If the purchase token can't be matched with any of our apps, then we will conclude that the purchase is not valid and return the error.
        if purchase_token_does_not_match_package_name?(error: e)
          raise PurchaseTokenMismatchException.new
        else
          raise e
        end
      end

      private

      sig { params(error: ::Google::Apis::Error).returns(T::Boolean) }
      def purchase_token_does_not_match_package_name?(error:)
        return false unless error.status_code == 400

        json = JSON.parse(error.body)
        return false unless json

        errors = json.dig("error", "errors")
        return false unless errors

        errors.any? { |e| e["reason"] == "purchaseTokenDoesNotMatchPackageName" }
      end
    end
  end
end
