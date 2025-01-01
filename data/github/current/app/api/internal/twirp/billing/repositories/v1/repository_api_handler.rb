# typed: true
# frozen_string_literal: true

require "monolith-twirp-billing-repositories"


module Api::Internal::Twirp::Billing
  module Repositories
    module V1
      class RepositoryAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["billing"]
        handles_service MonolithTwirp::Billing::Repositories::V1::RepositoryAPIService

        def get_repository_metadata(req, env)
          return Twirp::Error.invalid_argument("id is required") if req.id.blank? || req.id.zero?

          repository = ::Repositories::Public.get_active_or_deleted(req.id)
          return Twirp::Error.not_found("Repository #{req.id} not found") unless repository

          MonolithTwirp::Billing::Repositories::V1::GetRepositoryMetadataResponse.new(
            repository: {
              id: repository.id,
              is_public: repository.public,
            }
          )
        end
      end
    end
  end
end
