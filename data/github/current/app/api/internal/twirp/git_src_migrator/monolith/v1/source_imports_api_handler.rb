# typed: true
# frozen_string_literal: true

require "monolith-twirp-git_src_migrator-monolith"

module Api::Internal::Twirp::GitSrcMigrator
  module Monolith
    module V1
      # Handler for the MonolithTwirp::GitSrcMigrator::Monolith::V1::SourceImportsAPIService
      class SourceImportsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["git_src_migrator"]
        handles_service MonolithTwirp::GitSrcMigrator::Monolith::V1::SourceImportsAPIService

        # rubocop:disable Style/HashSyntax
        STATE_TWIRP_ENUM_MAP = {
          :MIGRATION_STATE_PENDING => "pending",
          :MIGRATION_STATE_IN_PROGRESS => "in_progress",
          :MIGRATION_STATE_SUCCEEDED => "succeeded",
          :MIGRATION_STATE_FAILED => "failed",
          :MIGRATION_STATE_FAILED_VALIDATION => "failed_validation",
        }.freeze
        # rubocop:enable Style/HashSyntax

        # Public: Implementation of the StopImport Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::GitSrcMigrator::Monolith::V1::StopImportRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::GitSrcMigrator::Monolith::V1::StopImportResponse, or a Twirp::Error.
        def stop_import(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "repository_id")
          end

          repository = T.cast(::Repositories.domain.by_id(req.repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          unless repository
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s)
          end

          if req.migration_state == :MIGRATION_STATE_INVALID
            return Twirp::Error.invalid_argument(
              "Must be :MIGRATION_STATE_PENDING, :MIGRATION_STATE_IN_PROGRESS, :MIGRATION_STATE_SUCCEEDED, :MIGRATION_STATE_FAILED, or :MIGRATION_STATE_FAILED_VALIDATION", argument: "migration_state")
          end

          if req.user_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "user_id", value: req.user_id.to_s)
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            ImportExport.domain.importing_stopped!(repository)

            # clear max object size if it was set prior during import
            repository.clear_max_object_size(repository.user)
          end

          migration_status = STATE_TWIRP_ENUM_MAP[req.migration_state]

          notifier = SourceImport::Notifier.new(
            repository:     repository,
            user:           user,
            status:         migration_status,
            failure_reason: req.failure_reason,
            error_details:  req.error_details
          )

          tags = ["rpc:stop_import", "status:#{migration_status}"]
          GitHub.dogstats.increment("github_importer_on_actions.import.completed", tags: tags)

          if notifier.notify_if_complete
            GlobalInstrumenter.instrument("repository.import_completed", {
              repository: repository,
              actor: user,
              completed_status: notifier.completed_status
            })
          end

          # Return nothing
          {}
        end

        # Public: Implementation of the UpdateImportStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::GitSrcMigrator::Monolith::V1::UpdateImportStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::GitSrcMigrator::Monolith::V1::UpdateImportStatusResponse, or a Twirp::Error.
        def update_import_status(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "repository_id")
          end

          repository = Repository.find_by(id: req.repository_id)
          unless repository
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s)
          end

          if req.migration_state == :MIGRATION_STATE_INVALID
            return Twirp::Error.invalid_argument(
              "Must be :MIGRATION_STATE_PENDING, :MIGRATION_STATE_IN_PROGRESS, :MIGRATION_STATE_SUCCEEDED, :MIGRATION_STATE_FAILED, or :MIGRATION_STATE_FAILED_VALIDATION", argument: "migration_state")
          end

          # Notify Websocket of change in state
          channel_data = { status: req.migration_state.to_s, timestamp: Time.now.utc.to_s, failure_reason: req.failure_reason, error_details: req.error_details }
          GitHub::WebSocket.notify_repository_channel repository, websocket_channel(repository), channel_data

          # Return nothing
          {}
        end

        private

        def websocket_channel(repo)
          GitHub::WebSocket::Channels.source_import(repo)
        end
      end
    end
  end
end
