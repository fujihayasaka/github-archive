# typed: true
# frozen_string_literal: true

module Octoshift
  module Service
    class CreateConnector < Base
      attr_reader :user, :owner, :name, :url, :connector_instance_type

      # user    - The User record starting the migration.
      # owner   - Login of the User or Organization that will own the imported resources.
      # name - The connector name
      # url - The base url
      # connector_instance_type - The connector type
      def initialize(user:, owner:, name:, url:, connector_instance_type:)
        @user = user
        @owner = owner
        @name = name
        @url = url
        @connector_instance_type = connector_instance_type
      end

      def call
        return unless authorization_policy.can_import_repo?(user: user, owner: owner)
        connector_response = twirp_create_connector
        return unless connector_response.has_key?(:connector_id)
        connector_response[:connector_id]
      end

      def twirp_create_connector
        # Call twirp handler with CreateConnectorRequest
        # Return CreateConnectorResponse
        # Right now we are stubbing this until we have
        #   the twrip handlers for CreateConnectorResponse
        {
          connector_id: SecureRandom.alphanumeric
        }
      end

      private

      def authorization_policy
        Octoshift::AuthorizationPolicy
      end
    end
  end
end
