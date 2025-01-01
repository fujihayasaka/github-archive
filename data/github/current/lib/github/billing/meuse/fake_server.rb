# typed: true
# frozen_string_literal: true

require "meuse/client"

module GitHub
  module Billing
    module Meuse
      class FakeServer
        def call(env)
          request = Rack::Request.new(env)
          case request.path
          when "/twirp/meuse.services.v1.MeteredUsage/CalculateUsageQuotes"
            usage_quote_request = ::Meuse::Services::V1::CalculateUsageQuotesRequest.decode(request.body.read)
            body = usage_quotes_response(usage_quote_request.proposed_usage)
            [200, { "Content-Type" => "application/protobuf" }, [body]]
          else
            [404, {}, ["This endpoint is either incorrect or hasn't been stubbed"]]
          end
        end

        private

        def usage_quotes_response(proposed_usage)
          response = ::Meuse::Services::V1::CalculateUsageQuotesResponse.new(
            usage_quotes: proposed_usage.map do |usage|
              usage_quote(product_name: usage.product_name, product_sku_name: usage.product_sku_name)
            end
          )
          ::Meuse::Services::V1::CalculateUsageQuotesResponse.encode(response)
        end

        def usage_quote(product_name:, product_sku_name:)
          {
            product_name: product_name,
            product_sku_name: product_sku_name,
            total_historical_usage: {
              quantity: 1000.0,
              estimated_cost: {
                subunits: 0
              }
            },
            marginal_proposed_usage: {
              quantity: 20.0,
            },
            total_proposed_usage: {
              estimated_cost: {
                subunits: 0
              },
            },
          }
        end
      end
    end
  end
end
