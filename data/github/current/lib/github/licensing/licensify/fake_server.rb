# typed: true
# frozen_string_literal: true

require "licensify/client"

module GitHub
  module Licensing
    module Licensify
      class FakeServer
        def self.call(env)
          request = Rack::Request.new(env)

          case request.path
          when "/twirp/licensify.services.v1.CustomerLicenseService/GetCustomerLicenses"
            response = ::Licensify::Services::V1::GetCustomerLicensesResponse.new({})
            encoded_response = ::Licensify::Services::V1::GetCustomerLicensesResponse.encode(response)
            [200, { "Content-Type" => "application/protobuf" }, [encoded_response]]
          when "/twirp/licensify.services.v1.CustomerLicenseService/GetLicenseeIds"
            response = ::Licensify::Services::V1::GetLicenseeIdsResponse.new({})
            encoded_response = ::Licensify::Services::V1::GetLicenseeIdsResponse.encode(response)
            [200, { "Content-Type" => "application/protobuf" }, [encoded_response]]
          else
            [404, {}, ["This endpoint is either incorrect or hasn't been stubbed"]]
          end
        end
      end
    end
  end
end
