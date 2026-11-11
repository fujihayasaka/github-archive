# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      # Handler for the MonolithTwirp::Elm::Actions::V1::ExportActionsSettingsAPIService
      class ExportActionsSettingsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Elm::Actions::V1::ExportActionsSettingsAPIService

        # Public: Implementation of the ExportActionsSettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Actions::V1::ExportActionsSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Elm::Actions::V1::ExportActionsSettingsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Actions::V1::ExportActionsSettingsRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_actions_settings(req, env)
          repository_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repository_id == 0

          repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          else
            Repository.find_by(id: repository_id)
          end

          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id").tap do |error|
              error.meta[:value] = repository_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_NOT_FOUND"
            end
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id").tap do |error|
              error.meta[:value] = repository_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_DELETED"
            end
          end

          {
            actions_settings: build_actions_settings(repository)
          }
        end

        private

        sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
        def build_actions_settings(repository)
          actions_permission = if repository.actions_disabled?
            :ACTIONS_PERMISSION_TYPE_DISABLED
          elsif repository.allows_all_actions?
            :ACTIONS_PERMISSION_TYPE_ALL_ENABLED
          elsif repository.allows_local_actions_only?
            :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
          elsif repository.allows_specified_actions?
            :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
          else
            # If repository inherits from organization/enterprise.
            # This should never happen since the above conditions should cover all cases.
            :ACTIONS_PERMISSION_TYPE_INHERITED
          end

          # Get allowlist patterns if they exist
          patterns = repository.highest_level_allowlist&.allowed_action_patterns&.map(&:value) || []

          {
            actions_permission: actions_permission,
            allows_github_owned_actions: repository.allows_github_owned_actions?,
            allows_verified_actions: repository.allows_verified_actions?,
            patterns: patterns,
            resource_id: repository.id.to_s, # Actions settings are tied to the repository
            repository_resource_id: repository.id.to_s
          }
        end
      end
    end
  end
end
