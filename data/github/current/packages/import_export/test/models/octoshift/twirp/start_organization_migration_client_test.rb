# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class StartOrganizationMigrationClientTest < GitHub::TestCase
      fixtures do
        @user_id = Faker::Number.number(digits: 5)
        @source_org_url = Faker::Internet.url
        @target_org_name = Faker::Alphanumeric.alpha
        @target_enterprise_id = Faker::Number.number(digits: 5)
        @source_access_token = SecureRandom.alphanumeric
        @target_access_token = SecureRandom.alphanumeric
      end

      test "starts a new migration" do
        org_migration = MonolithTwirp::Octoshift::Migrations::V1::OrgMigration.new(
          id: "5f8f84eef6ce3d00087a511b",
          source_org_url: @source_org_url,
          target_org_name: @target_org_name,
          migration_state: :ORG_MIGRATION_STATE_QUEUED
        )
        data = MonolithTwirp::Octoshift::Migrations::V1::StartOrgMigrationResponse.new(org_migration: org_migration)
        twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
        MonolithTwirp::Octoshift::Migrations::V1::StartOrgMigrationAPIClient.any_instance.
          stubs(:start_org_migration).
          with(
            user_id: @user_id,
            source_org_url: @source_org_url,
            target_org_name: @target_org_name,
            target_enterprise_id: @target_enterprise_id,
            source_access_token: @source_access_token,
            target_access_token: @target_access_token
          ).returns(twirp_client_response)

        client = Octoshift::Twirp::StartOrganizationMigrationClient.new
        response = client.start_org_migration(
          user_id: @user_id,
          source_org_url: @source_org_url,
          target_org_name: @target_org_name,
          target_enterprise_id: @target_enterprise_id,
          source_access_token: @source_access_token,
          target_access_token: @target_access_token
        )

        assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::OrgMigration, response
        assert_equal org_migration.id, response.id
      end

      test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
        twirp_error = ::Twirp::Error.internal("internal error", {})
        MonolithTwirp::Octoshift::Migrations::V1::StartOrgMigrationAPIClient.any_instance.
          stubs(:start_org_migration).
          with(
            user_id: @user_id,
            source_org_url: @source_org_url,
            target_org_name: @target_org_name,
            target_enterprise_id: @target_enterprise_id,
            source_access_token: @source_access_token,
            target_access_token: @target_access_token
          ).returns(stub(error: twirp_error))

        client = Octoshift::Twirp::StartOrganizationMigrationClient.new

        assert_raises(Octoshift::Twirp::Error) do
          client.start_org_migration(
            user_id: @user_id,
            source_org_url: @source_org_url,
            target_org_name: @target_org_name,
            target_enterprise_id: @target_enterprise_id,
            source_access_token: @source_access_token,
            target_access_token: @target_access_token
          )
        end
      end
    end
  end
end
