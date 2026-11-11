# typed: true
# frozen_string_literal: true

require "monolith-twirp-pages-pagesdeployerapi"

module Api::Internal::Twirp::Pages
  module Pagesdeployerapi
    module V1
      class ArtifactsApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["pages_deployer"].freeze
        handles_service MonolithTwirp::Pages::Pagesdeployerapi::V1::ArtifactsAPIService

        resolve_tenant_context do |req, _env|
          next nil unless req.respond_to?(:repository_id)
          Repositories::Public.resolve_tenant(id: req.repository_id)
        end

        # Public: Implementation of the GetArtifactDownloadUrl Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pages::Pagesdeployerapi::V1::GetArtifactDownloadUrlRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Pages::Pagesdeployerapi::V1::GetArtifactDownloadUrlResponse, or a Twirp::Error.
        def get_artifact_download_url(req, env)
          GetArtifactDownloadUrl.call(req, env)
        end
      end
    end
  end
end
