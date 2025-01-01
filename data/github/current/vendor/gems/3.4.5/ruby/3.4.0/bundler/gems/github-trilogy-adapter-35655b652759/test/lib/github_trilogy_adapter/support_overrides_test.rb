# frozen_string_literal: true

require "test_helper"

class GitHubTrilogyAdapter::SupportOverridesTest < TestCase
  setup do
    @adapter = ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(@configuration)
  end

  test "#supports_insert_raw_alias_syntax? returns false" do
    refute @adapter.supports_insert_raw_alias_syntax?
  end
end
