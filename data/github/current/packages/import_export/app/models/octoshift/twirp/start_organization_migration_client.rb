# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class StartOrganizationMigrationClient
      attr_reader :client

      # Public: Construct a StartOrganizationMigrationClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::StartOrgMigrationAPIClient.new(faraday_connection)
      end

      # Public: Starts a new organization migration.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # user_id - The ID of the user that wants to create an import.
      # target_org_name - The name of the target organization.
      # target_enterprise_id - The ID of the target enterprise that owns the organization.
      # source_access_token - The Octoshift migration source access token.
      # target_access_token - The Octoshift migration target access token.
      # source_org_url - The URL of the source organization.
      #
      # Returns the migration object.
      def start_org_migration(user_id:, target_org_name:, target_enterprise_id:,
                                        source_access_token:, target_access_token:, source_org_url:)
        response = client.start_org_migration(
          user_id: user_id,
          target_org_name: target_org_name,
          target_enterprise_id: target_enterprise_id,
          source_access_token: source_access_token,
          target_access_token: target_access_token,
          source_org_url: source_org_url
        )

        raise Error, response.error if response.error

        response.data.org_migration
      end
    end
  end
end
