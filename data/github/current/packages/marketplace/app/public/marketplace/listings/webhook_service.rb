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

        sorted_deliveries = T.must(webhook_deliveries).sort_by &:delivered_at
        if sorted_deliveries.last&.status_code == 200
          true
        else
          false
        end
      end

      # Get deliveries for webhook
      # Logs error with listing details if hook or hookshot is not found
      # Returns an array of webhook deliveries
      sig { returns(T.nilable(T::Array[Hookshot::Delivery])) }
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
        hookshot = Hookshot::Client.for_parent current_hook.hookshot_parent_id
        if !hookshot
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
        params_for_search = { limit: 15 }
        status, data = hookshot.deliveries_for_hook(current_hook.id, params_for_search)
        deliveries = data["deliveries"].present? ? Hookshot::Delivery.load(data["deliveries"]) : []
        deliveries
      end
    end
  end
end
