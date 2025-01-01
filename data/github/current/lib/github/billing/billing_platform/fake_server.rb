# typed: true
# frozen_string_literal: true

require "billing-platform/client"

module GitHub
  module Billing
    module BillingPlatform
      class FakeServer
        def call(env)
          request = Rack::Request.new(env)
          case request.path
          when "/twirp/billing_platform.api.v1.CustomerApi/UpsertCustomer"
            response = ::BillingPlatform::Api::V1::CreateCustomerResponse.new
            encoded_response = ::BillingPlatform::Api::V1::CreateCustomerResponse.encode(response)
            [200, { "Content-Type" => "application/protobuf" }, [encoded_response]]
          else
            [404, {}, ["This endpoint is either incorrect or hasn't been stubbed"]]
          end
        end
      end
    end
  end
end
