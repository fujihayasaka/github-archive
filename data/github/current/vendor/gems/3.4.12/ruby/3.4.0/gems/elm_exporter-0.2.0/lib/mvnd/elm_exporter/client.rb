# frozen_string_literal: true

require "faraday"
require_relative "api/v1/api_twirp"
require_relative "twirp_error"

module Mvnd
  module ElmExporter
    class Client
      def initialize(faraday)
        @faraday = faraday
      end

      # One-RPC round-trip used for the #4716 smoke test.
      # `status` is intentionally optional: it is a proto3 optional field, so
      # leaving it unset means "no filter" (server defaults to in-progress).
      def list_migrations(status: nil, page_size: 0, after: "")
        request = Api::V1::ListMigrationsRequest.new(page_size: page_size, after: after)
        request.status = status unless status.nil?

        unwrap(twirp_client.list_migrations(request))
      end

      # Prepares a migration but does not start it. `migrator_context` is an
      # already-built Api::V1::MigratorContext: the gem is a logic-free passthrough,
      # so callers construct the nested authentication message.
      # `target_visibility` is the proto3 RepositoryVisibility enum and is optional
      # (server defaults to INTERNAL when unset); all other fields are required.
      def create_migration(
        migrator_context:,
        source_organization_login:,
        source_repository_name:,
        target_organization_login:,
        target_repository_name:,
        migration_target_api_endpoint:,
        target_visibility: nil
      )
        request = Api::V1::CreateMigrationRequest.new(
          migrator_context: migrator_context,
          source_organization_login: source_organization_login,
          source_repository_name: source_repository_name,
          target_organization_login: target_organization_login,
          target_repository_name: target_repository_name,
          migration_target_api_endpoint: migration_target_api_endpoint,
        )
        request.target_visibility = target_visibility unless target_visibility.nil?

        unwrap(twirp_client.create_migration(request))
      end

      def get_migration_status(migration_id:)
        request = Api::V1::GetMigrationStatusRequest.new(migration_id: migration_id)

        unwrap(twirp_client.get_migration_status(request))
      end

      def start_migration(migration_id:, skip_preflight: false)
        request = Api::V1::StartMigrationRequest.new(
          migration_id: migration_id,
          skip_preflight: skip_preflight,
        )

        unwrap(twirp_client.start_migration(request))
      end

      def pause_migration(migration_id:)
        request = Api::V1::PauseMigrationRequest.new(migration_id: migration_id)

        unwrap(twirp_client.pause_migration(request))
      end

      # Interim alias: resume is StartMigration with preflight skipped, until a
      # dedicated ResumeMigration RPC exists. See github/migrations-vnext#5594.
      def resume_migration(migration_id:)
        start_migration(migration_id: migration_id, skip_preflight: true)
      end

      def terminate_migration(migration_id:)
        request = Api::V1::TerminateMigrationRequest.new(migration_id: migration_id)

        unwrap(twirp_client.terminate_migration(request))
      end

      def cutover_to_destination(migration_id:, force: false)
        request = Api::V1::CutoverToDestinationRequest.new(
          migration_id: migration_id,
          force: force,
        )

        unwrap(twirp_client.cutover_to_destination(request))
      end

      def revert_cutover(migration_id:)
        request = Api::V1::RevertCutoverRequest.new(migration_id: migration_id)

        unwrap(twirp_client.revert_cutover(request))
      end

      private

      # Returns the decoded response body, or raises TwirpError when the RPC
      # failed. Mirrors the original inline check in #list_migrations.
      def unwrap(response)
        return response.data if response.error.nil?

        raise TwirpError.new(twirp_response: response)
      end

      def twirp_client
        @twirp_client ||= Api::V1::MigrationManagerAPIClient.new(@faraday)
      end
    end
  end
end
