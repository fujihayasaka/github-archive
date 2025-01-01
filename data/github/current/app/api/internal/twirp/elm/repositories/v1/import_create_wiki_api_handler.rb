# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-repositories"

module Api::Internal::Twirp::Elm
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Elm::Repositories::V1::ImportCreateWikiAPIService
      class ImportCreateWikiAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext octoshift]
        handles_service MonolithTwirp::Elm::Repositories::V1::ImportCreateWikiAPIService

        # Public: Implementation of the ImportCreateWiki Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Repositories::V1::ImportCreateWikiRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Elm::Repositories::V1::ImportCreateWikiResponse, or a Twirp::Error.
        def import_create_wiki(req, env)
          # Validate repository_id parameter
          repo_id = T.unsafe(req).repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id == 0

          # Validate user_id parameter
          user_id = T.unsafe(req).user_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") if user_id == 0

          # Find and validate the repository
          repository = T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_NOT_FOUND")
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_DELETED")
          end

          # Find and validate the user
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("User not found", argument: "user_id", value: user_id.to_s, elm_error_code: "USER_NOT_FOUND")
          end

          # Initialize the wiki using the same logic as create_empty_wiki
          begin
            result = ActiveRecord::Base.connected_to(role: :writing) do
              repository.initialize_wiki(user)
            end

            # If initialize_wiki returns nil, it means either the user cannot edit wikis
            # or the wiki already exists
            if result.nil?
              return Twirp::Error.failed_precondition("Wiki cannot be created", argument: "repository_id", value: repo_id.to_s, elm_error_code: "WIKI_CREATION_NOT_ALLOWED")
            end

            { success: true }
          rescue => e
            GitHub.logger.error("Failed to initialize wiki", {
              "code.function" => "import_create_wiki",
              "gh.repo.id" => repo_id,
              "gh.user.id" => user_id,
              "exception.message" => e.message,
              "code.namespace" => "import_create_wiki_api_handler"
            })

            {
              success: false,
              error_message: "Failed to initialize wiki: #{e.message}"
            }
          end
        end
      end
    end
  end
end
