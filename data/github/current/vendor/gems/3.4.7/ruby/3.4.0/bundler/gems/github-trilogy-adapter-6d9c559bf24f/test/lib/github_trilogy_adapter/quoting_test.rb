# frozen_string_literal: true

require "test_helper"

class GitHubTrilogyAdapter::QuotingTest < TestCase
  setup do
    @adapter = ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(@configuration)
  end

  test "#quoted_true answers one" do
    assert_equal "1", @adapter.quoted_true
  end

  test "#quoted_false answers zero" do
    assert_equal "0", @adapter.quoted_false
  end
end
