# typed: true
# frozen_string_literal: true

require "json"
require "jwt"
require "faraday"

module Mobile
  module Apple
    # Client for the App Store Server API
    class AppStoreClient

      STOREKIT_PRODUCTION_URL = "https://api.storekit.itunes.apple.com".freeze
      STOREKIT_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com".freeze
      GITHUB_IOS_APP_BUNDLE_ID = "com.github.stormbreaker.prod".freeze

      # The server environment, either sandbox or production.
      #
      # [environment](https://developer.apple.com/documentation/appstoreserverapi/environment)
      class Environment < T::Enum

        enums do
          Production = new
          Sandbox = new
        end

        sig { params(string: T.nilable(String)).returns(T.nilable(Environment)) }
        def self.from_string(string)
          case string
          when "Production" then Production
          when "Sandbox" then Sandbox
          end
        end

        sig { returns(T::Boolean) }
        def production?
          self == Production
        end

        sig { returns(T::Boolean) }
        def sandbox?
          !production?
        end
      end

      # The status of an auto-renewable subscription.
      #
      # [status](https://developer.apple.com/documentation/appstoreserverapi/status)
      class SubscriptionStatus < T::Enum

        enums do
          Active = new
          Expired = new
          InBillingRetryPeriod = new
          InBillingGracePeriod = new
          Revoked = new
        end

        sig { params(integer: T.nilable(Integer)).returns(T.nilable(SubscriptionStatus)) }
        def self.from_raw(integer)
          case integer
          when 1 then Active
          when 2 then Expired
          when 3 then InBillingRetryPeriod
          when 4 then InBillingGracePeriod
          when 5 then Revoked
          else nil
          end
        end

        sig { returns(T::Boolean) }
        def not_active?
          !active?
        end

        sig { returns(T::Boolean) }
        def active?
          self == Active || self == InBillingGracePeriod || self == InBillingRetryPeriod
        end
      end

      # The cause of a purchase transaction, which indicates whether it’s a customer’s purchase or a renewal for an
      # auto-renewable subscription that the system initiates.
      #
      # [transactionReason](https://developer.apple.com/documentation/appstoreserverapi/transactionreason)
      class TransactionReason < T::Enum

        enums do
          Purchase = new
          Renewal = new
        end

        sig { params(value: T.nilable(String)).returns(T.nilable(TransactionReason)) }
        def self.from_raw(value)
          case value
          when "PURCHASE" then Purchase
          when "RENEWAL" then Renewal
          else nil
          end
        end
      end

      # A decoded payload that contains transaction information.
      class TransactionInfo < T::Struct

        # The unique identifier of the transaction.
        const :transaction_id, String

        # The transaction identifier of the original purchase.
        const :original_transaction_id, String

        # The unique identifier of subscription purchase events across devices, including subscription renewals.
        const :web_order_line_item_id, String

        # The bundle identifier of the app.
        const :bundle_id, String

        # The unique identifier of the product.
        const :product_id, String

        # The identifier of the subscription group to which the subscription belongs.
        const :subscription_group_identifier, String

        # The UNIX time, in milliseconds, that the App Store charged the customer’s account for a purchase,
        # restored product, subscription, or subscription renewal after a lapse.
        const :purchase_date, Time

        # The UNIX time, in milliseconds, that represents the purchase date of the original transaction identifier.
        const :original_purchase_date, Time

        # The UNIX time, in milliseconds, that the subscription expires or renews.
        const :expires_date, Time

        # The number of consumable products the customer purchased.
        const :quantity, Integer

        # The type of the in-app purchase.
        const :type, String

        # A string that describes whether the transaction was purchased by the customer, or is available to them through Family Sharing.
        const :in_app_ownership_type, String

        # The UNIX time, in milliseconds, that the App Store signed the JSON Web Signature (JWS) data.
        const :signed_date, Time

        # The server environment, either sandbox or production.
        const :environment, Environment

        # The reason for the purchase transaction, which indicates whether it’s a customer’s purchase or a renewal for
        # an auto-renewable subscription that the system initates.
        const :transaction_reason, T.nilable(TransactionReason)

        # The three-letter code that represents the country or region associated with the App Store storefront for the purchase.
        const :storefront, String

        # An Apple-defined value that uniquely identifies the App Store storefront associated with the purchase.
        const :storefront_id, String

        # An integer value that represents the price multiplied by 1000 of the in-app purchase or subscription offer
        # you configured in App Store Connect and that the system records at the time of the purchase. The currency
        # parameter indicates the currency of this price.
        const :price, Integer

        # The three-letter ISO 4217 currency code associated with the price parameter. This value is present only if
        # price is present.
        const :currency, String

        sig { params(signed_transaction_info: T.nilable(String)).returns(T.nilable(TransactionInfo)) }
        def self.from_signed_transaction_info(signed_transaction_info)
          return nil unless signed_transaction_info

          decoded = JWT.decode(signed_transaction_info, nil, false)

          # We expect the transaction_info to be a two-element array.
          return nil unless decoded.is_a?(Array) && decoded.length == 2

          transaction_info = decoded.first
          return nil unless transaction_info&.is_a?(Hash)

          environment = Environment.from_string(transaction_info.dig("environment"))
          return nil unless environment

          new(
            transaction_id: transaction_info.dig("transactionId"),
            original_transaction_id: transaction_info.dig("originalTransactionId"),
            web_order_line_item_id: transaction_info.dig("webOrderLineItemId"),
            bundle_id: transaction_info.dig("bundleId"),
            product_id: transaction_info.dig("productId"),
            subscription_group_identifier: transaction_info.dig("subscriptionGroupIdentifier"),
            purchase_date: Apple::parse_time(unix_time_in_milliseconds: transaction_info.dig("purchaseDate")),
            original_purchase_date: Apple::parse_time(unix_time_in_milliseconds: transaction_info.dig("originalPurchaseDate")),
            expires_date: Apple::parse_time(unix_time_in_milliseconds: transaction_info.dig("expiresDate")),
            quantity: transaction_info.dig("quantity"),
            type: transaction_info.dig("type"),
            in_app_ownership_type: transaction_info.dig("inAppOwnershipType"),
            signed_date: Apple::parse_time(unix_time_in_milliseconds: transaction_info.dig("signedDate")),
            environment: environment,
            transaction_reason: TransactionReason.from_raw(transaction_info.dig("transactionReason")),
            storefront: transaction_info.dig("storefront"),
            storefront_id: transaction_info.dig("storefrontId"),
            price: transaction_info.dig("price"),
            currency: transaction_info.dig("currency"),
          )
        end
      end

      # A decoded payload containing subscription renewal information for an auto-renewable subscription.
      class RenewalInfo < T:: Struct

        # The reason the subscription expired.
        const :expiration_intent, T.nilable(Integer)

        # The transaction identifier of the original purchase associated with this transaction.
        const :original_transaction_id, String

        # The identifier of the product that renews at the next billing period.
        const :auto_renew_product_id, String

        # The unique identifier of the product.
        const :product_id, String

        # The renewal status of the auto-renewable subscription.
        const :auto_renew_status, Integer

        # A Boolean value that indicates whether the App Store is attempting to automatically renew an expired subscription.
        const :is_in_billing_retry_period, T.nilable(T::Boolean)

        # The UNIX time, in milliseconds, that the App Store signed the JSON Web Signature (JWS) data.
        const :signed_date, Time

        # The server environment, either sandbox or production.
        const :environment, Environment

        # The earliest start date of an auto-renewable subscription in a series of subscription purchases that
        # ignores all lapses of paid service that are 60 days or fewer.
        const :recent_subscription_start_date, Time

        # The UNIX time, in milliseconds, that the most recent auto-renewable subscription purchase expires.
        const :renewal_date, Time

        sig { params(signed_renewal_info: T.nilable(String)).returns(T.nilable(RenewalInfo)) }
        def self.from_signed_renewal_info(signed_renewal_info)
          return nil unless signed_renewal_info

          decoded = JWT.decode(signed_renewal_info, nil, false)
          return nil unless decoded.is_a?(Array) && decoded.length == 2

          renewal_info = decoded.first
          return nil unless renewal_info&.is_a?(Hash)

          environment = Environment.from_string(renewal_info.dig("environment"))
          return nil unless environment

          RenewalInfo.new(
            expiration_intent: renewal_info.dig("expirationIntent"),
            original_transaction_id: renewal_info.dig("originalTransactionId"),
            auto_renew_product_id: renewal_info.dig("autoRenewProductId"),
            product_id: renewal_info.dig("productId"),
            auto_renew_status: renewal_info.dig("autoRenewStatus"),
            is_in_billing_retry_period: renewal_info.dig("isInBillingRetryPeriod"),
            signed_date: Apple::parse_time(unix_time_in_milliseconds: renewal_info.dig("signedDate")),
            environment: environment,
            recent_subscription_start_date: Apple::parse_time(unix_time_in_milliseconds: renewal_info.dig("recentSubscriptionStartDate")),
            renewal_date: Apple::parse_time(unix_time_in_milliseconds: renewal_info.dig("renewalDate"))
          )
        end
      end

      # The most recent App Store-signed transaction information and App Store-signed renewal information for
      # an auto-renewable subscription.
      class TransactionItem < T::Struct

        # The original transaction identifier of the auto-renewable subscription.
        const :original_transaction_id, String

        # The status of the auto-renewable subscription.
        const :status, SubscriptionStatus

        # The decoded transaction information which was signed by the App Store, in JWS format.
        const :transaction_info, T.nilable(TransactionInfo)

        # The decoded subscription renewal information signed by the App Store, in JSON Web Signature (JWS) format.
        const :renewal_info, T.nilable(RenewalInfo)

        sig { params(json: Hash).returns(TransactionItem) }
        def self.from_json(json)
          original_transaction_id = json.dig("originalTransactionId")
          raise SubscriptionResponseParseError.new unless original_transaction_id

          status_response = json.dig("status")
          status = SubscriptionStatus.from_raw(status_response)
          raise UnexpectedTransactionStatus.new unless status

          transaction_info = json.dig("signedTransactionInfo")
          renewal_info = json.dig("signedRenewalInfo")
          new(
            original_transaction_id: original_transaction_id,
            status: status,
            transaction_info: TransactionInfo.from_signed_transaction_info(transaction_info),
            renewal_info: RenewalInfo.from_signed_renewal_info(renewal_info)
          )
        end
      end

      # Information for auto-renewable subscriptions, including signed transaction information and signed renewal information,
      # for one subscription group.
      class SubscriptionGroupIdentifierItem < T::Struct

        # The subscription group identifier of the auto-renewable subscriptions in the lastTransactions array.
        const :subscription_group_identifier, String

        # An array of the most recent App Store-signed transaction information and App Store-signed renewal information
        # for all auto-renewable subscriptions in the subscription group.
        const :last_transactions, T::Array[TransactionItem]

        sig { params(json: Hash).returns(SubscriptionGroupIdentifierItem) }
        def self.from_json(json)
          subscription_group_identifier = json.dig("subscriptionGroupIdentifier")
          raise SubscriptionResponseParseError.new unless subscription_group_identifier

          last_transactions = json.dig("lastTransactions") || []
          new(
            subscription_group_identifier: subscription_group_identifier,
            last_transactions: last_transactions.collect(&TransactionItem.method(:from_json))
          )
        end
      end

      # A response that contains status information for all of a customer's auto-renewable subscriptions in your app.
      class StatusResponse < T::Struct

        # The server environment, sandbox or production, in which the App Store generated the response.
        const :environment, Environment

        # Your app's bundle identifier.
        const :bundle_id, String

        # An array of information for auto-renewable subscriptions, including App Store-signed transaction information
        # and App Store-signed renewal information.
        const :items, T::Array[SubscriptionGroupIdentifierItem]

        sig { params(json: Hash).returns(StatusResponse) }
        def self.from_json(json)
          environment = Environment.from_string(json.dig("environment"))
          raise SubscriptionResponseParseError.new unless environment

          bundle_id = json.dig("bundleId")
          raise SubscriptionResponseParseError.new unless bundle_id

          items_data = json.dig("data") || []

          new(
            environment: environment,
            bundle_id: bundle_id,
            items: items_data.collect(&SubscriptionGroupIdentifierItem.method(:from_json)).compact
          )
        end

        # Returns the latest subscription status for the given product id. If there is no
        # transaction data for the product id, then it returns `nil`.
        sig { params(product_id: String).returns(T.nilable(SubscriptionStatus)) }
        def subscription_status(product_id:)
          latest_transaction_item(product_id:)&.status
        end

        # Returns the latest transaction item for the given product id. If there is no
        # transaction data for the product id, then it returns `nil`.
        sig { params(product_id: String).returns(T.nilable(TransactionItem)) }
        def latest_active_transaction_item(product_id:)
          transaction_item = latest_transaction_item(product_id:)

          transaction_item&.status&.active? ? transaction_item : nil
        end

        # Returns the latest transaction item for the given product id. If there is no
        # transaction data for the product id, then it returns `nil`.
        sig { params(product_id: String).returns(T.nilable(TransactionItem)) }
        def latest_transaction_item(product_id:)
          items
            .map(&:last_transactions)
            .flatten
            .find { |transaction| transaction.transaction_info&.product_id == product_id }
        end
      end

      class BaseException < StandardError; end
      class SubscriptionResponseParseError < BaseException; end
      class UnexpectedResponseCode < BaseException; end
      class UnexpectedTransactionStatus < BaseException; end

      # Server errors
      class UnauthorizedError < BaseException; end
      class NotFoundError < BaseException; end
      class AccountNotFoundError < NotFoundError; end
      class AccountNotFoundRetryableError < NotFoundError; end
      class AppNotFoundError < NotFoundError; end
      class AppNotFoundRetryableError < NotFoundError; end
      class TransactionIdNotFoundError < NotFoundError; end
      class BadRequestException < BaseException; end
      class InvalidAppIdentifierError < BadRequestException; end
      class InvalidTransactionIdError < BadRequestException; end
      class InvalidStatusError < BadRequestException; end
      class RateLimitExceededError < BaseException; end
      class InternalServerError < BaseException; end
      class GeneralInternalError < InternalServerError; end
      class GeneralInternalRetryableError < InternalServerError; end

      attr_reader :connection, :key_id, :key_contents, :issuer_id, :bundle_id

      def self.production(key_id:, key_contents:, issuer_id:)
        connection = GitHub::FaradayClient::External.new(STOREKIT_PRODUCTION_URL) do |conn|
          conn.adapter Faraday.default_adapter
        end
        new(
          connection: connection,
          key_id: key_id,
          key_contents: key_contents,
          issuer_id: issuer_id,
          bundle_id: GITHUB_IOS_APP_BUNDLE_ID
        )
      end

      def self.sandbox(key_id:, key_contents:, issuer_id:)
        connection = GitHub::FaradayClient::External.new(STOREKIT_SANDBOX_URL) do |conn|
          conn.adapter Faraday.default_adapter
        end
        new(
          connection: connection,
          key_id: key_id,
          key_contents: key_contents,
          issuer_id: issuer_id,
          bundle_id: GITHUB_IOS_APP_BUNDLE_ID
        )
      end

      def initialize(connection:, key_id:, key_contents:, issuer_id:, bundle_id:)
        @connection = connection
        @connection.headers["Accept"] = "application/json"
        @connection.headers["Content-Type"] = "application/json"
        @key_id = key_id
        @key_contents = key_contents
        @issuer_id = issuer_id
        @bundle_id = bundle_id
      end

      # https://developer.apple.com/documentation/appstoreserverapi/get_all_subscription_statuses

      sig { params(original_transaction_id: String).returns(StatusResponse) }
      def get_all_subscription_statuses(original_transaction_id:)
        response = connection.get("/inApps/v1/subscriptions/#{original_transaction_id}") do |req|
          token = generate_token(bundle_id: bundle_id, issuer_id: issuer_id, key_id: key_id, key_contents: key_contents)
          req.headers["Authorization"] = "Bearer #{token}"
        end
        case response.status
        when 200
          body = JSON.parse(response.body) rescue (raise SubscriptionResponseParseError.new)
          StatusResponse.from_json(body)
        when 400
          body = JSON.parse(response.body) rescue nil
          raise BadRequestException.new unless body

          case body["errorCode"]
          when 4000002 then raise InvalidAppIdentifierError.new
          when 4000006 then raise InvalidTransactionIdError.new
          when 4000031 then raise InvalidStatusError.new
          else raise BadRequestException.new
          end
        when 401
          raise UnauthorizedError.new
        when 404
          body = JSON.parse(response.body) rescue nil
          raise NotFoundError.new unless body

          case body["errorCode"]
          when 4040001 then raise AccountNotFoundError.new
          when 4040010 then raise TransactionIdNotFoundError.new
          when 4040002 then raise AccountNotFoundRetryableError.new
          when 4040003 then raise AppNotFoundError.new
          when 4040004 then raise AppNotFoundRetryableError.new
          else raise NotFoundError.new
          end
        when 429
          raise RateLimitExceededError.new
        when 500
          body = JSON.parse(response.body) rescue nil
          raise InternalServerError.new unless body

          case body["errorCode"]
          when 5000000 then raise GeneralInternalError.new
          when 5000001 then raise GeneralInternalRetryableError.new
          else raise InternalServerError.new
          end
        else
          raise UnexpectedResponseCode.new
        end
      end

      private

      sig do
        params(
          bundle_id: String,
          issuer_id: String,
          key_id: String,
          key_contents: String
        )
        .returns(String)
      end
      def generate_token(bundle_id:, issuer_id:, key_id:, key_contents:)
        algo = "ES256"
        time = Time.now.utc
        issued_at = time.to_i
        expires_at = (time + (5 * 60)).to_i # now + 5 minutes
        audience = "appstoreconnect-v1"
        header = {
          alg: algo,
          typ: "JWT",
          kid: key_id
        }
        payload = {
          iss: issuer_id,
          iat: issued_at,
          exp: expires_at,
          aud: audience,
          bid: bundle_id
        }
        key = OpenSSL::PKey.read(key_contents)
        JWT.encode(payload, key, algo, header)
      end
    end

    def self.parse_time(unix_time_in_milliseconds:)
      Time.at(*unix_time_in_milliseconds.divmod(1000), :millisecond)
    end
  end
end
