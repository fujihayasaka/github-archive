# frozen_string_literal: true

require "test_helper"

class GitHubTrilogyAdapter::NativeDatabaseTypesTest < TestCase
  test "#native_database_types answers known types" do
    adapter = ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(@configuration)
    assert_equal GitHubTrilogyAdapter::NativeDatabaseTypes::NATIVE_DATABASE_TYPES, adapter.native_database_types
  end
end
