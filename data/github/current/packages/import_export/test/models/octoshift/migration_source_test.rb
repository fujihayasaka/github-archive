# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

require "test_helper"

module Octoshift
  class MigrationSourceTest < GitHub::TestCase
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
    end

    test "#platform_type_name returns MigrationSource" do
      assert_equal "MigrationSource", @migration_source.platform_type_name
    end

    test "@connector properties are properly delegated" do
      [:id, :name, :url, :owner_id, :owner_login].each do |property|
        assert_equal @connector.send(property), @migration_source.send(property)
      end
    end

    test "#type returns the connector instance type" do
      assert_equal @connector.connector_instance_type, @migration_source.type
    end
  end
end
