# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

require "test_helper"

module Octoshift
  class RepositoryMigrationTest < GitHub::TestCase
    setup do
      @connector = MonolithTwirp::Octoshift::Migrations::V1::Connector.new(
        id: Faker::Internet.uuid,
        connector_instance_type: :CONNECTOR_INSTANCE_TYPE_GITHUB_ARCHIVE,
        name: Faker::Alphanumeric.alpha,
        url: Faker::Internet.url,
        owner_id: rand(1000),
        owner_login: Faker::Internet.username
      )
      @migration_source = MigrationSource.new(@connector)

      @source_url = Faker::Internet.url
      @migration_state = :MIGRATION_STATE_QUEUED
      @migration = MonolithTwirp::Octoshift::Migrations::V1::Migration.new(
        id: Faker::Internet.uuid,
        repository_name: "repository-name",
        source_connector_id: @connector.id,
        source_url: @source_url,
        migration_state: @migration_state,
        continue_on_error: @continue_on_error
      )

      @repository_migration = RepositoryMigration.new(@migration, @migration_source)
    end

    test "#platform_type_name returns RepositoryMigration" do
      assert_equal "RepositoryMigration", @repository_migration.platform_type_name
    end

    test "@migration properties are properly delegated" do

      %i[id repository_name source_url failure_reason continue_on_error migration_log_url].each do |property|
        assert_equal @migration.send(property), @repository_migration.send(property)
      end
    end

    test "#migration_source returns the migration source" do
      assert_equal @migration_source, @repository_migration.migration_source
    end

    test "#state returns the migration state" do
      assert_equal @migration.migration_state, @repository_migration.state
    end

    test "#database_id returns the database id" do
      assert_equal @migration.id, @repository_migration.database_id
    end
  end
end
