# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class OrganizationMigrationClient
      attr_reader :client

      # Public: Construct a OrganizationMigrationClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::OrgMigrationAPIClient.new(faraday_connection)
      end

      # Public: Returns the org migration object.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # org_migration_id - is the id of the migration.
      #
      # Returns the migration object.
      def get_org_migration(org_migration_id:)
        response = client.get_org_migration(org_migration_id: org_migration_id)

        raise Error, response.error if response.error

        response.data.org_migration
      end
    end
  end
end
