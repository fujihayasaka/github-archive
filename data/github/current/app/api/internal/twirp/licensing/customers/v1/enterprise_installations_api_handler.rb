# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::EnterpriseInstallationsAPIService
      class EnterpriseInstallationsApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Customers::V1::EnterpriseInstallationsAPIService

        # Public: Implementation of the EnterpriseInstallations Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsResponse, Twirp::Error))
        end
        def get_enterprise_installations(req, env)
          unless customer_id = id_argument(req.customer_id)
            return Twirp::Error.invalid_argument("customer_id is required", argument: "customer_id")
          end

          handle_request(customer_id)
        end

        private

        sig { params(customer_id: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsResponse, Twirp::Error)) }
        def handle_request(customer_id)

          business = Customer.find_by(id: customer_id)&.business

          enterprise_installations = T.let([], T::Array[MonolithTwirp::Licensing::Customers::V1::EnterpriseInstallation])

          if business
            enterprise_installations = business.enterprise_installations.map do |enterprise_installation|
              MonolithTwirp::Licensing::Customers::V1::EnterpriseInstallation.new(id: enterprise_installation.id)
            end
          end

          MonolithTwirp::Licensing::Customers::V1::GetEnterpriseInstallationsResponse.new(
            enterprise_installations: enterprise_installations,
          )
        end
      end
    end
  end
end
