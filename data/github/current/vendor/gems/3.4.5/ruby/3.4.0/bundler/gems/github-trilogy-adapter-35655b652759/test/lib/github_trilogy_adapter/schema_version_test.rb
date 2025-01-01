# frozen_string_literal: true

require "test_helper"

class GitHubTrilogyAdapter::SchemaVersionTest < TestCase
  test "#schema_version answers version" do
    Dir.chdir(@fixtures_path) do # Picks up hard coded `structure.sql` path.
      adapter = ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(@configuration)
      version = Digest::SHA1.file("db/structure.sql").hexdigest +
                GitHubTrilogyAdapter::SchemaVersion::SCHEMA_VERSION

      assert_equal version, adapter.schema_version
    end
  end
end
