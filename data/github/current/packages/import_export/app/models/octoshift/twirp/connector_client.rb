# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class ConnectorClient
      attr_reader :client

      # Public: Construct a CreateImportClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::ConnectorAPIClient.new(faraday_connection)
      end

      # Public: Creates a connector.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # connector_instance_type - the type of connection such as GitLab, AZURE_DEVOPS etc.
      # name - the name of the connector
      # url - the base url
      # access_token - the Authentication token identifying the person importing
      # owner_id - the ID of the organization or user that owns the migration.
      # owner_login - login of the organization or user account that owns the migration.
      # github_pat - the GitHub Personal Access Token of the user importing to the target repository.
      #
      # Returns the connector object.
      def create_connector(connector_instance_type:, name:, url:, access_token:, owner_id:, owner_login:, github_pat:)
        response = client.create_connector(
            connector_instance_type: connector_instance_type,
            name: name,
            url: url,
            access_token: access_token,
            owner_id: owner_id,
            owner_login: owner_login,
            github_pat: github_pat
        )

        raise Error, response.error if response.error

        response.data.connector
      end

      # Public: Get a connector.
      #
      # Raises an Octoshift::Twirp::ConnectorNotFound if the request fails due to the connector not being found.
      # Raises an Octoshift::Twirp::Error if the request fails for any other reason.
      #
      # connector_id - the id of the connector.
      #
      # Returns the connector object.
      def get_connector(connector_id:)
        response = client.get_connector(connector_id: connector_id)

        if response.error
          raise ConnectorNotFound, response.error.msg if response.error.code == :not_found

          raise Error, response.error
        end

        response.data.connector
      end
    end
  end
end
