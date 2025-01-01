# typed: true
# frozen_string_literal: true

require "monolith-twirp-billing-products"

module Api::Internal::Twirp::Billing
  module Products
    module V1
      # Handler for the MonolithTwirp::Billing::Products::V1::ZuoraProductAPIService
      class ZuoraProductAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["billing"]
        handles_service MonolithTwirp::Billing::Products::V1::ZuoraProductAPIService

        # Public: Implementation of the SyncZuoraProducts Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Billing::Products::V1::SyncZuoraProductsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Billing::Products::V1::SyncZuoraProductsResponse, or a Twirp::Error.
        def sync_zuora_products(req, env)
          parsed_products = req.zuora_products.map do |product|
            {
              zuora_product_id: product.zuora_product_id.to_s,
              product_type: product.product_type.to_s,
              zuora_product_rate_plans: product.zuora_product_rate_plans.map do |rate_plan|
                {
                  zuora_product_rate_plan_id: rate_plan.zuora_product_rate_plan_id,
                  effective_on: Time.at(rate_plan.effective_on.seconds),
                }
              end
            }
          end
          Billing::Zuora::SyncMeteredProductUuidsFromZuoraJob.perform_later(
            zuora_products: parsed_products,
          )
          {
            result: "ack",
          }
        end
      end
    end
  end
end
