# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class MigrationClientTest < GitHub::TestCase
      include OctoshiftTestHelpers

      fixtures do
        @migration_id = "5f9215c9333c32003a42623f"
        @owner_id = Faker::Number.number(digits: 6)
        @owner_login = Faker::Alphanumeric.alpha
        @migration_state = :MIGRATION_STATE_QUEUED
        @source_connector_id = "5f8db4894f2188215e3aace2"
        @source_identifier_url = Faker::Internet.url
        @failure_reason = ""
        @migration_log_url = ""
      end

      context "#get_migration_status" do
        test "gets the migration status" do
          migration_status = MonolithTwirp::Octoshift::Migrations::V1::MigrationStatus.new(
            id: @migration_id,
            migration_state: :MIGRATION_STATE_QUEUED
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::GetMigrationStatusResponse.new(migration_status: migration_status)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migration_status).
            with(migration_id: @migration_id).
            returns(twirp_client_response)

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migration_status(migration_id: @migration_id)

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::MigrationStatus, response
          assert_equal response.id, @migration_id
          assert_equal response.migration_state, :MIGRATION_STATE_QUEUED
          assert_empty response.failure_reason
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migration_status).
            with(migration_id: @migration_id).
            returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.get_migration_status(migration_id: @migration_id)
          end
        end
      end

      context "#get_migration" do
        test "gets the migration" do
          @migration_log_url = Faker::Internet.url
          migration = MonolithTwirp::Octoshift::Migrations::V1::Migration.new(
            id: @migration_id,
            source_connector_id: @source_connector_id,
            source_url: @source_identifier_url,
            migration_state: @migration_state,
            failure_reason: @failure_reason,
            migration_log_url: @migration_log_url
          )
          data = MonolithTwirp::Octoshift::Migrations::V1::GetMigrationResponse.new(migration: migration)
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migration).
            with(migration_id: @migration_id).
            returns(twirp_client_response)

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migration(migration_id: @migration_id)

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response
          assert_equal @migration_id, response.id
          assert_equal @source_connector_id, response.source_connector_id
          assert_equal @source_identifier_url, response.source_url
          assert_equal @migration_state, response.migration_state
          assert_equal @failure_reason, response.failure_reason
          assert_equal @migration_log_url, response.migration_log_url
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migration).
            with(migration_id: @migration_id).
            returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.get_migration(migration_id: @migration_id)
          end
        end
      end

      context "#get_migrations" do
        test "gets the migrations for owner_id" do
          connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
          succeeded_migration = generate_migration_twirp_object(
            connector_id: connector_id,
            migration_state: :MIGRATION_STATE_SUCCEEDED,
            created_at: DateTime.new(2021, 6, 4)
          )

          in_progress_migration = generate_migration_twirp_object(
            connector_id: connector_id,
            migration_state: :MIGRATION_STATE_IN_PROGRESS,
            created_at: DateTime.new(2021, 6, 5)
          )

          stub_migrations_client_response_for_migrations(
            migrations: [succeeded_migration, in_progress_migration],
            owner_id: @owner_id
          )

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migrations(owner_id: @owner_id)

          assert_equal 2, response.count
          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
          assert_equal succeeded_migration.id, response.first.id
          assert_equal connector_id, response.first.source_connector_id
          assert_equal succeeded_migration.source_url, response.first.source_url
          assert_equal :MIGRATION_STATE_SUCCEEDED, response.first.migration_state
          assert_empty response.first.failure_reason
          assert_equal succeeded_migration.created_at, response.first.created_at

          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.last
          assert_equal in_progress_migration.id, response.last.id
          assert_equal connector_id, response.last.source_connector_id
          assert_equal in_progress_migration.source_url, response.last.source_url
          assert_equal :MIGRATION_STATE_IN_PROGRESS, response.last.migration_state
          assert_empty response.last.failure_reason
          assert_equal succeeded_migration.created_at, response.first.created_at
        end

        test "gets the migrations for specified state" do
          connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
          stub_migrations_client_get_migrations_for_state(
            connector_id: connector_id,
            owner_id: @owner_id,
            migration_state: :MIGRATION_STATE_SUCCEEDED
          )

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migrations(
            owner_id: @owner_id,
            migration_state: :MIGRATION_STATE_SUCCEEDED
          )

          assert_equal 1, response.count
          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
          assert_equal :MIGRATION_STATE_SUCCEEDED, response.first.migration_state
        end

        test "gets the migrations for specified repository name" do
          connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
          stub_migrations_client_get_migrations_for_repository_name(
            connector_id: connector_id,
            owner_id: @owner_id,
            repository_name: "excellent-repository-name"
          )

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migrations(
            owner_id: @owner_id,
            repository_name: Google::Protobuf::StringValue.new(value: "excellent-repository-name")
          )

          assert_equal 1, response.count
          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
          assert_equal "excellent-repository-name", response.first.repository_name
        end

        test "gets the migrations for specified limit" do
          connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
          in_progress_migration = generate_migration_twirp_object(
            connector_id: connector_id,
            migration_state: :MIGRATION_STATE_IN_PROGRESS,
            created_at: DateTime.new(2021, 6, 5)
          )

          stub_migrations_client_response_for_migrations(
            migrations: [in_progress_migration],
            owner_id: @owner_id,
            limit: 1
          )

          client = Octoshift::Twirp::MigrationClient.new
          response = client.get_migrations(
            owner_id: @owner_id,
            limit: 1
          )

          assert_equal 1, response.count
          assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
          assert_equal :MIGRATION_STATE_IN_PROGRESS, response.first.migration_state
          assert_equal in_progress_migration.created_at, response.first.created_at
        end

        context "with cursor" do
          test "gets the migrations after specified cursor" do
            connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
            succeeded_migration = generate_migration_twirp_object(
              connector_id: connector_id,
              migration_state: :MIGRATION_STATE_SUCCEEDED,
              created_at: DateTime.new(2021, 6, 4)
            )

            in_progress_migration = generate_migration_twirp_object(
              connector_id: connector_id,
              migration_state: :MIGRATION_STATE_IN_PROGRESS,
              created_at: DateTime.new(2021, 6, 5)
            )

            cursor = Platform::ConnectionWrappers::CursorGenerator.generate_cursor([succeeded_migration.created_at.to_time.iso8601, succeeded_migration.id], version: :v2)

            stub_migrations_client_response_for_migrations(
              migrations: [in_progress_migration],
              owner_id: @owner_id,
              direction: :MIGRATION_ORDER_DIRECTION_ASC,
              limit: 2,
              cursor: cursor
            )

            client = Octoshift::Twirp::MigrationClient.new
            response = client.get_migrations(
              owner_id: @owner_id,
              direction: :MIGRATION_ORDER_DIRECTION_ASC,
              limit: 2,
              cursor: cursor,
            )

            assert_equal 1, response.count
            assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
            assert_equal :MIGRATION_STATE_IN_PROGRESS, response.first.migration_state
            assert_equal in_progress_migration.created_at, response.first.created_at
          end

          test "gets the migrations before specified cursor" do
            connector_id = stub_connector_client(owner_id: @owner_id, owner_login: @owner_login)
            succeeded_migration = generate_migration_twirp_object(
              connector_id: connector_id,
              migration_state: :MIGRATION_STATE_SUCCEEDED,
              created_at: DateTime.new(2021, 6, 4)
            )

            in_progress_migration = generate_migration_twirp_object(
              connector_id: connector_id,
              migration_state: :MIGRATION_STATE_IN_PROGRESS,
              created_at: DateTime.new(2021, 6, 5)
            )

            cursor = Platform::ConnectionWrappers::CursorGenerator.generate_cursor([in_progress_migration.created_at.to_time.iso8601, in_progress_migration.id], version: :v2)

            stub_migrations_client_response_for_migrations(
              migrations: [succeeded_migration],
              owner_id: @owner_id,
              direction: :MIGRATION_ORDER_DIRECTION_DSC,
              limit: 2,
              cursor: cursor,
            )

            client = Octoshift::Twirp::MigrationClient.new
            response = client.get_migrations(
              owner_id: @owner_id,
              direction: :MIGRATION_ORDER_DIRECTION_DSC,
              limit: 2,
              cursor: cursor
            )

            assert_equal 1, response.count
            assert_instance_of MonolithTwirp::Octoshift::Migrations::V1::Migration, response.first
            assert_equal :MIGRATION_STATE_SUCCEEDED, response.first.migration_state
            assert_equal succeeded_migration.created_at, response.first.created_at
          end
        end

        test "raises Octoshift::Twirp::InvalidCursorError when the Twirp API responds with an invalid cursor error" do
          twirp_error = ::Twirp::Error.internal("`some cursor` does not appear to be a valid cursor.", { "cause" => "CursorGenerator::InvalidCursor" })
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migrations).
            with(
              owner_id: @owner_id,
              order_by: :MIGRATION_ORDER_FIELD_CREATED_AT,
              direction: :MIGRATION_ORDER_DIRECTION_ASC,
              cursor: "some cursor",
              limit: 101
            ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::InvalidCursorError) do
            client.get_migrations(
              owner_id: @owner_id,
              cursor: "some cursor"
            )
          end
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with an unhandled ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:get_migrations).
            with(
              owner_id: @owner_id,
              order_by: :MIGRATION_ORDER_FIELD_CREATED_AT,
              direction: :MIGRATION_ORDER_DIRECTION_ASC,
              limit: 101
            ).returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.get_migrations(
              owner_id: @owner_id
            )
          end
        end
      end

      context "abort_migration" do
        test "returns an empty hash" do
          data = MonolithTwirp::Octoshift::Migrations::V1::AbortMigrationResponse.new
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:abort_migration).
            with(migration_id: @migration_id).
            returns(twirp_client_response)

          client = Octoshift::Twirp::MigrationClient.new
          response = client.abort_migration(migration_id: @migration_id)

          assert_instance_of Hash, response
          assert_empty response
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:abort_migration).
            with(migration_id: @migration_id).
            returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.abort_migration(migration_id: @migration_id)
          end
        end
      end

      context "abort_queued_migrations" do
        test "returns an empty hash" do
          data = MonolithTwirp::Octoshift::Migrations::V1::AbortQueuedMigrationsResponse.new
          twirp_client_response = ::Twirp::ClientResp.new(data: data, error: nil)
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:abort_queued_migrations).
            with(customer_id: @owner_id, is_business: false).
            returns(twirp_client_response)

          client = Octoshift::Twirp::MigrationClient.new
          response = client.abort_queued_migrations(customer_id: @owner_id, is_business: false)

          assert_instance_of Hash, response
          assert_empty response
        end

        test "raises Octoshift::Twirp::Error when the Twirp API responds with a ::Twirp::Error" do
          twirp_error = ::Twirp::Error.internal("internal error", {})
          MonolithTwirp::Octoshift::Migrations::V1::MigrationAPIClient.any_instance.
            stubs(:abort_queued_migrations).
            with(customer_id: @owner_id, is_business: false).
            returns(stub(error: twirp_error))

          client = Octoshift::Twirp::MigrationClient.new

          assert_raises(Octoshift::Twirp::Error) do
            client.abort_queued_migrations(customer_id: @owner_id, is_business: false)
          end
        end
      end
    end
  end
end
