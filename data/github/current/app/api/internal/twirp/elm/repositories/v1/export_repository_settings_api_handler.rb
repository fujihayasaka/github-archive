# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-repositories"

module Api::Internal::Twirp::Elm
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Elm::Repositories::V1::ExportRepositorySettingsAPIService
      class ExportRepositorySettingsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Elm::Repositories::V1::ExportRepositorySettingsAPIService

        # Public: Implementation of the ExportRepositorySettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Repositories::V1::ExportRepositorySettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Elm::Repositories::V1::ExportRepositorySettingsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Repositories::V1::ExportRepositorySettingsRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_repository_settings(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id == 0


          repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          else
            Repository.find_by(id: repo_id)
          end
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_NOT_FOUND"
            end
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_DELETED"
            end
          end
          {
            repository_settings: build_repository_settings(repository)
          }
        end

        sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
        def build_repository_settings(repository)
          {
            are_vulnerability_alerts_enabled: repository.vulnerability_alerts_enabled?,
            is_dependency_graph_enabled: repository.dependency_graph_enabled?,
            is_git_lfs_enabled: repository.git_lfs_enabled?
          }
        end
      end
    end
  end
end
