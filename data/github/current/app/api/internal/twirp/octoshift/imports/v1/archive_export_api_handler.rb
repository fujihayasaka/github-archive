# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ArchiveExportAPIService.
      class ArchiveExportAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::ArchiveExportAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        MAX_THROTTLE_RETRIES = 5

        def get_archive_export_status(req, env)
          if req.owner_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_login")
          end

          if req.archive_export_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "archive_export_id")
          end

          owner = replica(Organization).find_by(login: req.owner_login)
          unless owner
            return Twirp::Error.not_found("Organization not found.", argument: "owner_login", value: req.owner_login)
          end

          archive_export = replica(Migration).find_by(id: req.archive_export_id, owner: owner)

          unless archive_export
            return Twirp::Error.not_found("Archive Export not found.", argument: "archive_export_id", value: req.archive_export_id.to_s)
          end

          build_archive_export_status_hash(archive_export)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        def get_archive_export_url(req, env)
          if req.owner_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_login")
          end

          if req.archive_export_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "archive_export_id")
          end

          owner = replica(Organization).find_by(login: req.owner_login)
          unless owner
            return Twirp::Error.not_found("Organization not found.", argument: "owner_login", value: req.owner_login)
          end

          archive_export = replica(Migration).find_by(id: req.archive_export_id, owner: owner)

          unless archive_export
            return Twirp::Error.not_found("Archive Export not found.", argument: "archive_export_id", value: req.archive_export_id.to_s)
          end

          file = archive_export.file
          unless file
            return Twirp::Error.not_found("Archive Export file not found.", argument: "archive_export_id", value: req.archive_export_id.to_s)
          end

          file.download

          { archive_url: file.download_url(actor: archive_export.owner) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        # Private: Converts the Migration object to the Twirp response
        # ArchiveExportStatusResponse.
        #
        # archive_export - The migration object.
        #
        # Returns an Hash object with migration data that matches the
        # Twirp definition.
        def build_archive_export_status_hash(archive_export)
          state = archive_export.current_state.name

          {
            created_at: archive_export.created_at.utc,
            state: map_archive_export_state_to_twirp_enum(state)
          }
        end

        def map_archive_export_state_to_twirp_enum(state)
          map =
            {
              pending: :ARCHIVE_EXPORT_STATE_PENDING,
              exporting: :ARCHIVE_EXPORT_STATE_EXPORTING,
              exported: :ARCHIVE_EXPORT_STATE_EXPORTED,
              failed: :ARCHIVE_EXPORT_STATE_FAILED
            }
          map[state]
        end
      end
    end
  end
end
