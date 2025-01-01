# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class StartMigrationClientTest < GitHub::TestCase
      fixtures do
        @user_id = Faker::Number.number(digits: 5)
        @repository_name = Faker::Alphanumeric.alpha
        @source_connector_id = "5f8db4894f2188215e3aace2"
        @source_identifier_url = Faker::Internet.url
        @migration_state = :MIGRATION_STATE_QUEUED
        @failure_reason = ""
        @continue_on_error = Faker::Boolean.boolean
        @git_archive_url = Faker::Internet.url
        @metadata_archive_url = Faker::Internet.url
        @access_token = SecureRandom.alphanumeric
        @github_pat = SecureRandom.alphanumeric
        @skip_releases = Faker::Boolean.boolean
        @target_repo_visibility = "private"
        @target_repo_visibility_enum = :REPOSITORY_VISIBILITY_PRIVATE
        @lock_source = false
      end

      context "#start_migration without archive URLs" do
        test "starts a new migration" do
          migration = MonolithTwirp::Octoshift::Migrations::V1::Migration.new(
            id: "5f8f84eef6ce3d00087a511c",
            source_connector_id: @source_connector_id,
            source_url: @source_identifier_url,
            continue_on_error: @continue_on_error
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::StartMigrationResponse.new(migration: migration)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::StartMigrationAPIClient.any_instance.
            stubs(:start_migration).
            with(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              git_archive_url: "",
              metadata_archive_url: "",
              access_token: @access_token,
              github_pat: @github_pat,
              skip_releases: @skip_releases,
              target_repo_visibility: @target_repo_visibility_enum,
              should_lock_source: @lock_source
            ).returns(twirp_client_response)

          client = Octoshift::Twirp::StartMigrationClient.new
          response = client.start_migration(
            user_id: @user_id,
            repository_name: @repository_name,
            source_connector_id: @source_connector_id,
            source_identifier_url: @source_identifier_url,
            continue_on_error: @continue_on_error,
            access_token: @access_token,
            github_pat: @github_pat,
            skip_releases: @skip_releases,
            target_repo_visibility: @target_repo_visibility,
            lock_source: @lock_source
          )

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response
          assert_equal migration.id, response.id
          assert_equal migration.source_connector_id, response.source_connector_id
          assert_equal migration.source_url, response.source_url
          assert_equal migration.migration_state, response.migration_state
          assert_equal migration.failure_reason, response.failure_reason
          assert_equal migration.continue_on_error, response.continue_on_error
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::StartMigrationAPIClient.any_instance.
            stubs(:start_migration).
            with(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              git_archive_url: "",
              metadata_archive_url: "",
              access_token: @access_token,
              github_pat: @github_pat,
              skip_releases: false,
              target_repo_visibility: @target_repo_visibility_enum,
              should_lock_source: @lock_source
            ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::StartMigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.start_migration(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              access_token: @access_token,
              github_pat: @github_pat,
              target_repo_visibility: @target_repo_visibility,
              lock_source: @lock_source
            )
          end
        end
      end

      context "#start_migration with archive URLs" do
        test "starts a new migration" do
          migration = MonolithTwirp::Octoshift::Migrations::V1::Migration.new(
            id: "5f8f84eef6ce3d00087a511c",
            source_connector_id: @source_connector_id,
            source_url: @source_identifier_url,
            continue_on_error: @continue_on_error
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::StartMigrationResponse.new(migration: migration)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::StartMigrationAPIClient.any_instance.
            stubs(:start_migration).
            with(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              git_archive_url: @git_archive_url,
              metadata_archive_url: @metadata_archive_url,
              access_token: @access_token,
              github_pat: @github_pat,
              skip_releases: @skip_releases,
              target_repo_visibility: @target_repo_visibility_enum,
              should_lock_source: @lock_source
            ).returns(twirp_client_response)

          client = Octoshift::Twirp::StartMigrationClient.new
          response = client.start_migration(
            user_id: @user_id,
            repository_name: @repository_name,
            source_connector_id: @source_connector_id,
            source_identifier_url: @source_identifier_url,
            continue_on_error: @continue_on_error,
            git_archive_url: @git_archive_url,
            metadata_archive_url: @metadata_archive_url,
            access_token: @access_token,
            github_pat: @github_pat,
            skip_releases: @skip_releases,
            target_repo_visibility: @target_repo_visibility,
            lock_source: @lock_source
          )

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response
          assert_equal migration.id, response.id
          assert_equal migration.source_connector_id, response.source_connector_id
          assert_equal migration.source_url, response.source_url
          assert_equal migration.migration_state, response.migration_state
          assert_equal migration.failure_reason, response.failure_reason
          assert_equal migration.continue_on_error, response.continue_on_error
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::StartMigrationAPIClient.any_instance.
            stubs(:start_migration).
            with(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              git_archive_url: @git_archive_url,
              metadata_archive_url: @metadata_archive_url,
              access_token: @access_token,
              github_pat: @github_pat,
              skip_releases: false,
              target_repo_visibility: @target_repo_visibility_enum,
              should_lock_source: @lock_source
            ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::StartMigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.start_migration(
              user_id: @user_id,
              repository_name: @repository_name,
              source_connector_id: @source_connector_id,
              source_identifier_url: @source_identifier_url,
              continue_on_error: @continue_on_error,
              git_archive_url: @git_archive_url,
              metadata_archive_url: @metadata_archive_url,
              access_token: @access_token,
              github_pat: @github_pat,
              target_repo_visibility: @target_repo_visibility,
              lock_source: @lock_source
            )
          end
        end
      end
    end
  end
end
