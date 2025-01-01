# typed: true
# frozen_string_literal: true

module Mobile
  module Apple
    # Service for calling Apple App Store API. It leverages `AppStoreClient` to make the actual API calls. It handles
    # the logic for falling back to the sandbox environment if the production environment returns a transaction not found.
    class AppStoreService

      sig { returns(AppStoreService) }
      def self.from_config
        key_id = GitHub.apple_app_store_api_key_id
        key_contents = GitHub.apple_app_store_api_key_contents
        issuer_id = GitHub.apple_app_store_api_issuer_id

        new(key_id:, key_contents:, issuer_id:)
      end

      def initialize(key_id:, key_contents:, issuer_id:)
        @production = AppStoreClient.production(key_id: key_id, key_contents: key_contents, issuer_id: issuer_id)
        @sandbox = AppStoreClient.sandbox(key_id: key_id, key_contents: key_contents, issuer_id: issuer_id)
      end

      # Main entry point for getting the subscription summary for a transaction. This method will return
      # a list of active products and other information about the subscription relevant for billing system updating.
      #
      # Note: This method calls AppStoreClient#get_all_subscription_statuses which can raise errors.
      # For more info, see the AppStoreClient#get_all_subscription_statuses method.
      #
      # This method can return different original_transaction_id values for the passed in original_transaction_id.
      # You should always use the returned original_transaction_id values, per product, as contained in
      # the returned SubscriptionSummary struct.
      sig { params(original_transaction_id: String).returns(SubscriptionSummary) }
      def get_subscription_summary(original_transaction_id:)
        status_response = get_all_subscription_statuses(original_transaction_id:)

        SubscriptionSummary.from_status_response(status_response)
      end

      # Call Apple's production environment first for a transaction ID and if its not found in
      # there then call Apple's sandbox environment.
      #
      # Note: This method calls AppStoreClient#get_all_subscription_statuses which can raise errors.
      # For more info, see the AppStoreClient#get_all_subscription_statuses method.
      sig { params(original_transaction_id: String).returns(AppStoreClient::StatusResponse) }
      def get_all_subscription_statuses(original_transaction_id:)
        production.get_all_subscription_statuses(original_transaction_id: original_transaction_id)
      rescue AppStoreClient::TransactionIdNotFoundError
        sandbox.get_all_subscription_statuses(original_transaction_id: original_transaction_id)
      end

      private

      attr_reader :production, :sandbox
    end
  end
end
