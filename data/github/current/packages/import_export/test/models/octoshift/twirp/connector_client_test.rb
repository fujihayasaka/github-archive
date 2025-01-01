# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class ConnectorClientTest < GitHub::TestCase
      fixtures do
        @connector_instance_type = :CONNECTOR_INSTANCE_TYPE_GITHUB_ARCHIVE
        @name = Faker::Alphanumeric.alpha
        @url = Faker::Internet.url
        @access_token = SecureRandom.alphanumeric
        @connector_id = Faker::Internet.uuid
        @owner_id = Faker::Number.number(digits: 6)
        @owner_login = Faker::Alphanumeric.alpha
        @github_pat = SecureRandom.alphanumeric
      end

      context "#create_connector" do
        test "creates a new connector" do
          connector = MonolithTwirp::Octoshift::Migrations::V1::Connector.new(
              id: Faker::Internet.uuid,
              connector_instance_type: @connector_instance_type,
              name: @name,
              url: @url,
              owner_id: @owner_id,
              owner_login: @owner_login
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::CreateConnectorResponse.new(connector: connector)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::ConnectorAPIClient.any_instance.
              stubs(:create_connector).
              with(
                  connector_instance_type: @connector_instance_type,
                  name: @name,
                  url: @url,
                  access_token: @access_token,
                  owner_id: @owner_id,
                  owner_login: @owner_login,
                  github_pat: @github_pat
              ).returns(twirp_client_response)

          client = Octoshift::Twirp::ConnectorClient.new
          response = client.create_connector(
              connector_instance_type: @connector_instance_type,
              name: @name,
              url: @url,
              access_token: @access_token,
              owner_id: @owner_id,
              owner_login: @owner_login,
              github_pat: @github_pat
          )

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Connector, response
          assert_equal connector.id, response.id
          assert_equal connector.connector_instance_type, response.connector_instance_type
          assert_equal connector.name, response.name
          assert_equal connector.url, response.url
          assert_equal connector.owner_id, response.owner_id
          assert_equal connector.owner_login, response.owner_login
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::ConnectorAPIClient.any_instance.
              stubs(:create_connector).
              with(
                  connector_instance_type: @connector_instance_type,
                  name: @name,
                  url: @url,
                  access_token: @access_token,
                  owner_id: @owner_id,
                  owner_login: @owner_login,
                  github_pat: @github_pat
              ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::ConnectorClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.create_connector(
                connector_instance_type: @connector_instance_type,
                name: @name,
                url: @url,
                access_token: @access_token,
                owner_id: @owner_id,
                owner_login: @owner_login,
                github_pat: @github_pat
            )
          end
        end
      end

      context "#get_connector" do
        test "get a connector" do
          connector = MonolithTwirp::Octoshift::Migrations::V1::Connector.new(
            id: @connector_id,
            connector_instance_type: @connector_instance_type,
            name: @name,
            url: @url
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::GetConnectorResponse.new(connector: connector)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::ConnectorAPIClient.any_instance.
              stubs(:get_connector).
              with(
                connector_id: @connector_id
              ).returns(twirp_client_response)

          client = Octoshift::Twirp::ConnectorClient.new
          response = client.get_connector(
            connector_id: @connector_id
          )

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Connector, response
          assert_equal response.id, connector.id
          assert_equal response.connector_instance_type, connector.connector_instance_type
          assert_equal response.name, connector.name
          assert_equal response.url, connector.url
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::ConnectorAPIClient.any_instance.
              stubs(:get_connector).
              with(
                connector_id: @connector_id
              ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::ConnectorClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.get_connector(
              connector_id: @connector_id
            )
          end
        end
      end
    end
  end
end
