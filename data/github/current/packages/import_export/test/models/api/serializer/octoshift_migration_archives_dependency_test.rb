# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OctoshiftMigrationArchivesDependencyTest < Api::SerializerTestCase
  fixtures do
    @octoshift_migration_archive = create(:octoshift_migration_archive)
  end

  context "#octoshift_migration_archive" do
    test "returns the expected hash" do
      octoshift_migration_archive = T.unsafe(self).octoshift_migration_archive(@octoshift_migration_archive)

      expected_octoshift_migration_archive = {
        "guid" => @octoshift_migration_archive.guid,
        "node_id" => @octoshift_migration_archive.global_relay_id,
        "name" => @octoshift_migration_archive.name,
        "size" => @octoshift_migration_archive.size,
        "uri" => @octoshift_migration_archive.gei_uri,
        "created_at" => @octoshift_migration_archive.created_at.iso8601(3)
      }

      assert_equal expected_octoshift_migration_archive, octoshift_migration_archive
    end
  end
end
