# typed: true
# frozen_string_literal: true

require "monolith-twirp-pages-pagesdeployerapi"

module Api::Internal::Twirp::Pages
  module Pagesdeployerapi
    module V1
      class AccessTokenApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["pages_deployer"].freeze
        handles_service MonolithTwirp::Pages::Pagesdeployerapi::V1::AccessTokenAPIService

        CODEPATH_PAGES_ACCESS_TOKEN_HANDLER = "pages_access_token_api_handler/get_access_token".freeze

        # Public: Implementation of the GetAccessToken Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pages::Pagesdeployerapi::V1::GetAccessTokenRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Pages::Pagesdeployerapi::V1::GetAccessTokenResponse, or a Twirp::Error.
        def get_access_token(req, env)
          return Twirp::Error.not_found("github pages app not found", argument: "repository_id") unless GitHub.pages_github_app.present?
          repository_id = req.repository_id
          repository = Repository.find_by(id: repository_id.to_i)
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          installation = IntegrationInstallation
            .with_repository(repository)
            .where(integration_id: GitHub.pages_github_app.id)
            .first
          return Twirp::Error.not_found("installation not found", argument: "repository_id") unless installation
          token =
            begin
              result = ScopedIntegrationInstallation::Creator
                . perform_with_cache(installation, repositories: [repository], entry_point: :pages_builder_github_app_token)

              if result.failed?
                return Twirp::Error.internal("failed to create token", meta: { error: result.error })
              end
              _, token = AuthenticationToken.create_for(result.installation, code_path: CODEPATH_PAGES_ACCESS_TOKEN_HANDLER)
              token
            end
          { access_token: token }
        end
      end
    end
  end
end
