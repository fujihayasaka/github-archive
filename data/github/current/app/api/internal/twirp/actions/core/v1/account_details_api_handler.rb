# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::AccountDetailsAPIService
      class AccountDetailsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::AccountDetailsAPIService

        exempt_from_tenant_context_requirement(
          only: %i[
            get_account_details
          ]
        )

        resolve_tenant_context only: %i[
          get_account_details_for_repository
        ] do |req, _env|
          case req
          when MonolithTwirp::Actions::Core::V1::GetAccountDetailsForRepositoryRequest
            next nil unless req.repository_id&.global_id.present?

            begin
              repo_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id&.global_id).last
              next Repositories::Public.resolve_tenant(id: repo_id)
            rescue Platform::Errors::NotFound, ActiveRecord::RecordNotFound => err
              GitHub.logger.info(
                "unable to resolve tenant", {
                  :exception => err,
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "gh.repo.global_id" => req.repository_id&.global_id
              })

              # We're returning nil for tenant context here so that the API handler can return the appropriate error.
              next nil
            end
          end
        end

        # Public: Implementation of the GetAccountDetails Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetAccountDetailsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetAccountDetailsResponse, or a Twirp::Error.
        def get_account_details(req, env)
          GetAccountDetails.call(req)
        end

        # Public: Implementation of the GetAccountDetailsForRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetAccountDetailsForRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetAccountDetailsForRepositoryResponse, or a Twirp::Error.
        def get_account_details_for_repository(req, env)
          GetAccountDetailsForRepository.call(req)
        end
      end
    end
  end
end
