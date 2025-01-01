# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class MigrationClient
      attr_reader :client

      # Public: Construct a MigrationClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.new(faraday_connection)
      end

      # Public: Returns the status of a migration.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # migration_id - is the id of the migration.
      #
      # Returns the migration_status object.
      def get_migration_status(migration_id:)
        response = client.get_migration_status(migration_id: migration_id)

        raise Error, response.error if response.error

        response.data.migration_status
      end

      # Public: Returns the migration object.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # migration_id - is the id of the migration.
      #
      # Returns the migration object.
      def get_migration(migration_id:)
        response = client.get_migration(migration_id: migration_id)

        raise Error, response.error if response.error

        response.data.migration
      end

      # Public: Returns the migrations for owner_id.
      #
      # owner_id - the ID of the organization that owns the migration.
      # migration_state - the state to filter migration results.
      # repository_name - optionally filter the results by a repository name.
      # order_by - the field to order migration results (defaults to created_at)
      # direction - the direction to order migration results (defaults to ascending)
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # Returns an array of migrations.
      def get_migrations(
        owner_id:, migration_state: nil, repository_name: nil, order_by: :MIGRATION_ORDER_FIELD_CREATED_AT, direction:
        :MIGRATION_ORDER_DIRECTION_ASC, limit: Octoshift::Twirp::TWIRP_CURSOR_LIMIT, cursor: nil
      )
        client_args = {
          owner_id: owner_id,
          order_by: order_by,
          direction: direction
        }

        client_args[:migration_state] = migration_state if migration_state.present?
        client_args[:repository_name] = repository_name if repository_name
        client_args[:limit] = limit if limit.present?
        client_args[:cursor] = cursor if cursor.present?

        response = client.get_migrations(**client_args)

        if response.error
          if response.error.msg.include?("does not appear to be a valid cursor")
            raise InvalidCursorError, response.error
          else
            raise Error, response.error
          end
        end

        response.data.migrations
      end

      # Public: Abort a migration.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # migration_id - is the id of the migration.
      #
      # Returns an empty hash.
      def abort_migration(migration_id:)
        response = client.abort_migration(migration_id: migration_id)

        raise Error, response.error if response.error

        {}
      end

      # Public: Aborts all the migrations queued for a given owner_id
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # owner_id - is the id of the organization that is queued the migrations
      #
      # Returns an empty hash.
      def abort_queued_migrations(customer_id:, is_business:)
        response = client.abort_queued_migrations(customer_id: customer_id, is_business: is_business)

        raise Error, response.error if response.error

        {}
      end
    end
  end
end
