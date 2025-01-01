# typed: true
# frozen_string_literal: true

module Mobile
  module Apple
    class SubscriptionSummary < T::Struct
      extend T::Sig

      const :environment, AppStoreClient::Environment

      const :active_pro_original_transaction_id, T.nilable(String)

      const :active_copilot_original_transaction_id, T.nilable(String)

      def pro?
        active_pro_original_transaction_id.present?
      end

      def copilot?
        active_copilot_original_transaction_id.present?
      end

      def production?
        environment == AppStoreClient::Environment::Production
      end

      sig { params(status_response: AppStoreClient::StatusResponse).returns(SubscriptionSummary) }
      def self.from_status_response(status_response)
        environment = status_response.environment
        active_pro_original_transaction_id = status_response.latest_active_transaction_item(product_id: PRO_PRODUCT_ID)&.original_transaction_id
        active_copilot_original_transaction_id = status_response.latest_active_transaction_item(product_id: COPILOT_PRODUCT_ID)&.original_transaction_id

        new(
          environment:,
          active_pro_original_transaction_id:,
          active_copilot_original_transaction_id:
        )
      end

      sig { params(value: T.nilable(String)).returns(T.nilable(Mobile::Apple::SubscriptionSummary)) }
      def self.deserialize(value)
        return nil if value.blank?

        deserialized_summary = JSON.parse(value, symbolize_names: true)

        return nil unless deserialized_summary

        # Default to production environment if the environment is not passed in
        environment = AppStoreClient::Environment.from_string(deserialized_summary[:environment]) || AppStoreClient::Environment::Production

        new(
          environment:,
          active_pro_original_transaction_id: deserialized_summary[:active_pro_original_transaction_id],
          active_copilot_original_transaction_id: deserialized_summary[:active_copilot_original_transaction_id]
        )
      end
    end
  end
end
