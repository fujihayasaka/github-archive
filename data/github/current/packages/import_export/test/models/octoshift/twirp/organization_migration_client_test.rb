# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class OrganizationMigrationClientTest < GitHub::TestCase
      include OctoshiftTestHelpers

      fixtures do
        @org_migration_id = "5f9215c9333c32003a42623f"
        @user_id = Faker::Number.number(digits: 5)
        @source_org_name = Faker::Alphanumeric.alpha
        @source_org_url = Faker::Internet.url
        @target_org_name = Faker::Alphanumeric.alpha
        @target_enterprise_id = Faker::Number.number(digits: 5)
        @migration_state = :ORG_MIGRATION_STATE_QUEUED
        @remaining_count = Google::Protobuf::Int64Value.new(value: Faker::Number.number(digits: 1)).freeze
        @total_repo_count = Google::Protobuf::Int64Value.new(value: Faker::Number.number(digits: 2)).freeze
      end

      context "#get_org_migration" do
        test "gets the org migration" do
          org_migration = MonolithTwirp::Octoshift::Migrations::V1::OrgMigration.new(
            id: @org_migration_id,
            source_org_name: @source_org_name,
            source_org_url: @source_org_url,
            migration_state: @migration_state,
            target_org_name: @target_org_name,
            target_enterprise_id: @target_enterprise_id,
            total_repositories_count: @total_repo_count,
            remaining_repositories_count: @remaining_count
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::GetOrgMigrationResponse.new(org_migration: org_migration)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::OrgMigrationAPIClient.any_instance.
            stubs(:get_org_migration).
            with(org_migration_id: @org_migration_id).
            returns(twirp_client_response)

          client = Octoshift::Twirp::OrganizationMigrationClient.new
          response = client.get_org_migration(org_migration_id: @org_migration_id)

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::OrgMigration, response
          assert_equal @org_migration_id, response.id
          assert_equal @source_org_name, response.source_org_name
          assert_equal @source_org_url, response.source_org_url
          assert_equal @migration_state, response.migration_state
          assert_equal @target_org_name, response.target_org_name
          assert_equal @target_enterprise_id, response.target_enterprise_id
          assert_equal @total_repo_count, response.total_repositories_count
          assert_equal @remaining_count, response.remaining_repositories_count
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::OrgMigrationAPIClient.any_instance.
            stubs(:get_org_migration).
            with(org_migration_id: @org_migration_id).
            returns(stub(error: twirp_error))

          client = Octoshift::Twirp::OrganizationMigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.get_org_migration(org_migration_id: @org_migration_id)
          end
        end
      end
    end
  end
end
