# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ArchiveExportAPIService.
      class ArchiveExportAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability
        include Imports::V1::Helpers::LegacyMigrationHelper

        handles_service MonolithTwirp::Octoshift::Imports::V1::ArchiveExportAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]
        MAX_THROTTLE_RETRIES = 5

        # On Proxima (multi-tenant), the Migrations domain does not have business_id
        # populated on migration records, so tenant-scoped queries would fail to find them.
        # Exempt these endpoints so queries run unscoped. This is safe because
        # the handler is only accessible to the internal octoshift client.
        exempt_from_tenant_context_requirement only: %i[
          get_legacy_migration
          get_migration_failed_models
          extend_archive_ttl
        ]

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

        # Public: Fetch metadata for a LegacyMigration.
        #
        # Accepts database ID, global relay ID, or GUID.
        #
        # Returns migration metadata used by Migrator chatops
        # commands such as `.migrator migration_info`.
        def get_legacy_migration(req, env)
          if req.migration_id.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "migration_id")
          end

          migration = find_legacy_migration(req.migration_id)
          return legacy_migration_not_found(req.migration_id) unless migration

          build_legacy_migration_hash(migration)
        end

        # Public: Return migratable resources that failed to import
        # for a given LegacyMigration.
        #
        # Used by Migrator chatops `.migrator failed_models`.
        #
        # Returns an array of failed model metadata.
        def get_migration_failed_models(req, env)
          if req.migration_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "migration_id")
          end

          migration = find_legacy_migration_by_id(req.migration_id)
          return legacy_migration_not_found(req.migration_id.to_s) unless migration

          {
            failed_models: build_failed_models(migration)
          }
        end

        # Public: Extend the archive TTL for a LegacyMigration.
        #
        # Used by Migrator chatops `.migrator extend_archive_life`.
        #
        # Returns the new archive expiry timestamp.
        def extend_archive_ttl(req, env)
          if req.migration_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "migration_id")
          end

          if req.days <= 0
            return Twirp::Error.invalid_argument("must be positive integer", argument: "days")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            migration = Migration.find_by(id: req.migration_id)
            return legacy_migration_not_found(req.migration_id.to_s) unless migration

            unless migration.file
              return Twirp::Error.not_found(
                "Archive Export file not found.",
                argument: "migration_id",
                value: migration.id.to_s
              )
            end

            new_expiry = extend_archive_ttl_for!(migration, req.days)

            { new_expiry: new_expiry }
          end
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
