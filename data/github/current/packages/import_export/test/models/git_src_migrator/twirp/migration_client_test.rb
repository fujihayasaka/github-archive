# typed: true
# frozen_string_literal: true

require "test_helper"

module GitSrcMigrator
  module Twirp
    class MigrationClientTest < GitHub::TestCase
      setup do
        @migration_client = GitSrcMigrator::Twirp::MigrationClient.new
      end

      context "#new" do
        test "initializes a new MigrationClient instance" do
          assert_instance_of GitSrcMigrator::Twirp::MigrationClient, @migration_client
        end

        context "with a faraday_connection parameter" do
          test "initializes a new MigrationClient instance" do
            migration_client = GitSrcMigrator::Twirp::MigrationClient.new(faraday_connection: GitHub::FaradayClient::Internal.new)

            assert_instance_of GitSrcMigrator::Twirp::MigrationClient, migration_client
          end
        end
      end

      context "#get_migration" do
        context "when passing an id" do
          test "returns a MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration instance with migration data" do
            migration = MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration.new(
              id: 1,
              state: :MIGRATION_STATE_PENDING,
              actions_logs: "example_actions_logs",
              actions_run_url: "example_actions_run_url",
              failure_reason: "example_failure_reason"
            )

            twirp_client_response = ::Twirp::ClientResp.new(
              data: MonolithTwirp::GitSrcMigrator::Migrations::V1::GetMigrationResponse.new(migration: migration)
            )

            @migration_client.client.expects(:get_migration).with(id: 1, repository_id: nil).returns(twirp_client_response)

            get_migration = @migration_client.get_migration(id: 1)

            assert_equal get_migration, migration
          end
        end

        context "when passing a repository_id" do
          test "returns a MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration instance with migration data" do
            migration = MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration.new(
              id: 1,
              state: :MIGRATION_STATE_PENDING,
              actions_logs: "example_actions_logs",
              actions_run_url: "example_actions_run_url",
              failure_reason: "example_failure_reason"
            )

            twirp_client_response = ::Twirp::ClientResp.new(
              data: MonolithTwirp::GitSrcMigrator::Migrations::V1::GetMigrationResponse.new(migration: migration)
            )

            @migration_client.client.expects(:get_migration).with(id: nil, repository_id: 1).returns(twirp_client_response)

            get_migration = @migration_client.get_migration(repository_id: 1)

            assert_equal get_migration, migration
          end
        end

        context "when passing an id and repository_id" do
          test "returns a MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration instance with migration data" do
            migration = MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration.new(
              id: 1,
              state: :MIGRATION_STATE_PENDING,
              actions_logs: "example_actions_logs",
              actions_run_url: "example_actions_run_url",
              failure_reason: "example_failure_reason"
            )

            twirp_client_response = ::Twirp::ClientResp.new(
              data: MonolithTwirp::GitSrcMigrator::Migrations::V1::GetMigrationResponse.new(migration: migration)
            )

            @migration_client.client.expects(:get_migration).with(id: 1, repository_id: 1).returns(twirp_client_response)

            get_migration = @migration_client.get_migration(id: 1, repository_id: 1)

            assert_equal get_migration, migration
          end
        end

        context "with a Twirp error" do
          test "raises a GitSrcMigrator::Twirp::Error error" do
            twirp_error = ::Twirp::Error.not_found("Migration not found")
            twirp_client_response = ::Twirp::ClientResp.new(error: twirp_error)

            @migration_client.client.expects(:get_migration).with(id: 2, repository_id: nil).returns(twirp_client_response)

            error = assert_raises GitSrcMigrator::Twirp::Error do
              @migration_client.get_migration(id: 2)
            end

            assert_equal twirp_error.to_s, error.message
          end
        end
      end

      context "#start_migration" do
        test "returns the migration database ID" do
          migration = MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration.new(
            id: 1,
            state: :MIGRATION_STATE_PENDING,
            actions_logs: "example_actions_logs",
            actions_run_url: "example_actions_run_url",
            failure_reason: "example_failure_reason"
          )

          twirp_client_response = ::Twirp::ClientResp.new(
            data: MonolithTwirp::GitSrcMigrator::Migrations::V1::GetMigrationResponse.new(migration: migration)
          )

          start_migration_params = {
            source_url: "https://example.com",
            source_type: :SOURCE_TYPE_GITHUB,
            source_access_token: "example_access_token",
            git_archive_url: "https://example.com",
            repository_id: 1,
            target_owner_id: 1,
            target_ssh_url: "https://example.com",
            source_username: "example_username",
            tags: ["example_tag"],
            user_id: 2
          }

          @migration_client.client.expects(:start_migration).with(**start_migration_params).returns(twirp_client_response)

          start_migration = @migration_client.start_migration(**start_migration_params)

          assert_equal start_migration, migration.id
        end

        context "without source_access_token, git_archive_url, source_username, or tags parameters" do
          test "returns the migration database ID" do
            migration = MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration.new(
              id: 1,
              state: :MIGRATION_STATE_PENDING,
              actions_logs: "example_actions_logs",
              actions_run_url: "example_actions_run_url",
              failure_reason: "example_failure_reason"
            )

            twirp_client_response = ::Twirp::ClientResp.new(
              data: MonolithTwirp::GitSrcMigrator::Migrations::V1::GetMigrationResponse.new(migration: migration)
            )

            @migration_client.client.expects(:start_migration).with(
              source_url: "https://example.com",
              source_type: :SOURCE_TYPE_GITHUB,
              source_access_token: nil,
              git_archive_url: nil,
              repository_id: 1,
              target_owner_id: 1,
              target_ssh_url: "https://example.com",
              source_username: nil,
              tags: [],
              user_id: 2
            ).returns(twirp_client_response)

            start_migration = @migration_client.start_migration(
              source_url: "https://example.com",
              source_type: :SOURCE_TYPE_GITHUB,
              repository_id: 1,
              target_owner_id: 1,
              target_ssh_url: "https://example.com",
              user_id: 2
            )

            assert_equal start_migration, migration.id
          end
        end

        context "with a Twirp error" do
          test "raises a GitSrcMigrator::Twirp::Error error" do
            twirp_error = ::Twirp::Error.invalid_argument("must be non-empty", { "argument" => "source_url" })
            twirp_client_response = ::Twirp::ClientResp.new(error: twirp_error)

            start_migration_params = {
              source_url: "",
              source_type: :SOURCE_TYPE_GITHUB,
              source_access_token: "example_access_token",
              git_archive_url: "https://example.com",
              repository_id: 1,
              target_owner_id: 1,
              target_ssh_url: "https://example.com",
              source_username: "example_username",
              tags: ["example_tag"],
              user_id: 2
            }

            @migration_client.client.expects(:start_migration).with(**start_migration_params).returns(twirp_client_response)

            error = assert_raises GitSrcMigrator::Twirp::Error do
              @migration_client.start_migration(**start_migration_params)
            end

            assert_equal twirp_error.to_s, error.message
          end
        end
      end
    end
  end
end
