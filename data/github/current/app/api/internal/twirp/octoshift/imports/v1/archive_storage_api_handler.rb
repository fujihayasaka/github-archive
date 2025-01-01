# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ArchiveStorageAPIService
      class ArchiveStorageAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ArchiveStorageAPIService

        # Implementation of the GetArchiveStorageMetadata Twirp RPC.
        #
        # @param [MonolithTwirp::Octoshift::Imports::V1::GetArchiveStorageMetadataRequest] req The Twirp request.
        # @param [Hash] env The Twirp environment.
        # @return [Hash] Archive storage metadata.
        def get_archive_storage_metadata(req, env)
          if req.organization_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          if req.guid.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "guid")
          end

          archive = replica(OctoshiftMigrationArchive).find_by(guid: req.guid, organization_id: req.organization_id)

          unless archive
            return Twirp::Error.not_found("Archive not found.", argument: "guid", value: req.guid)
          end

          { metadata: build_archive_hash(archive) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Implementation of the DeleteArchive Twirp RPC.
        #
        # @param [MonolithTwirp::Octoshift::Imports::V1::DeleteArchiveRequest] req The Twirp request.
        # @param [Hash] env The Twirp environment.
        # @return [Hash] Archive storage metadata.
        def delete_archive(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id") if req.organization_id.zero?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "guid") if req.guid.empty?

          OctoshiftMigrationArchive.with_write do
            octoshift_migration_archive = OctoshiftMigrationArchive.find_by(guid: req.guid, organization_id: req.organization_id)

            unless octoshift_migration_archive
              return Twirp::Error.not_found("Archive not found.", argument: "guid", value: req.guid)
            end

            octoshift_migration_archive.destroy!

            { metadata: build_archive_hash(octoshift_migration_archive) }
          end

        end

        private

        def build_archive_hash(archive)
          {
            id: archive.id,
            guid: archive.guid,
            name: archive.name,
            size: archive.size,
            url: archive.download_url(actor: archive.organization)
          }
        end
      end
    end
  end
end
