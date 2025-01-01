# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

require "test_helper"

module Octoshift
  class OrganizationMigrationTest < GitHub::TestCase
    setup do
      @id = Faker::Internet.uuid
      @source_org_name = Faker::Internet.username
      @target_org_name = Faker::Internet.username
      @source_org_url = Faker::Internet.url
      @target_enterprise_id = Faker::Number.number
      @failure_reason = "Some failure"

      @migration = MonolithTwirp::Octoshift::Migrations::V1::OrgMigration.new(
        id: @id,
        source_org_name: @source_org_name,
        source_org_url: @source_org_url,
        target_enterprise_id: @target_enterprise_id,
        failure_reason: @failure_reason
      )

      @org_migration = OrganizationMigration.new(@migration)
    end

    test "#platform_type_name returns OrganizationMigration" do
      assert_equal "OrganizationMigration", @org_migration.platform_type_name
    end

    test "@org_migration properties are properly delegated" do

      %i[id source_org_name target_org_name source_org_url target_enterprise_id failure_reason].each do |property|
        assert_equal @migration.send(property), @org_migration.send(property)
      end
    end

    test "#database_id returns the database id" do
      assert_equal @migration.id, @org_migration.database_id
    end
  end
end
