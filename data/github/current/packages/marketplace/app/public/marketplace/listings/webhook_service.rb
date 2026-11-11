# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class WebhookService
      include GitHub::Memoizer

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { params(listing: Marketplace::Listing).void }
      def initialize(listing:)
        @listing = listing
      end

      delegate :webhook, :name, to: :listing, private: true

      sig { returns(T::Boolean) }
      def no_deliveries_for_hook?
        webhook.present? && webhook_deliveries.blank?
      end

      sig { returns(String) }
      def hook_text
        if webhook.present?
          text = "The listing has provided a webhook"
          is_webhook_check_successful? ? "#{text} and it is working." : "#{text} but it is not working."
        else
          "Listing did not provide a webhook."
        end
      end

      private

      # Checks if lastest webhook delivery was successful
      sig { returns(T::Boolean) }
      def is_webhook_check_successful?
        return false if webhook_deliveries.blank?

        T.unsafe(webhook_deliveries)["status"] == 200
      end

      # Get deliveries for webhook
      # Logs error with listing details if hook or hookshot is not found
      # Returns a status hash from the statuses endpoint
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      memoize def webhook_deliveries
        return unless webhook.present?

        current_hook = Hook.find_by(id: webhook.id)
        if !current_hook
          GitHub.logger.info("Webhook deliveries could not be fetched",
            {
              "code.namespace" => "Marketplace::Listings::WebhookService",
              "code.function" => "webhook_deliveries",
              "gh.marketplace.hook_id" => webhook.id,
              "gh.marketplace.listing.name" => name
            }
          )
          return
        end

        webhook_deliveries_from_statuses(current_hook)
      end

      # Get status using the statuses endpoint
      # Returns a hash with status information
      sig { params(current_hook: Hook).returns(T.nilable(T::Hash[String, T.untyped])) }
      def webhook_deliveries_from_statuses(current_hook)
        hookshot_client = HookDeliveriesClient.new(current_hook)
        response_code, statuses = hookshot_client.statuses_for_hooks([current_hook.id])

        if response_code != 200
          GitHub.logger.info("Webhook deliveries could not be fetched",
            {
              "code.namespace" => "Marketplace::Listings::WebhookService",
              "code.function" => "webhook_deliveries_from_statuses",
              "gh.marketplace.hook_id" => webhook.id,
              "gh.marketplace.listing.name" => name,
              "response_code" => response_code
            }
          )
          return
        end

        status_data = statuses[current_hook.id.to_s]
        return nil if status_data.nil?

        status_data
      end
    end
  end
end
