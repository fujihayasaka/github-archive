# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetSyncStatusTest < GitHub::TestCase
  test "gets and sets sync status" do
    assert_nil Asset::SyncStatus.get(:all)
    Asset::SyncStatus.set(:all, :foo)
    assert_equal "foo", Asset::SyncStatus.get(:all)
  end

  test "validates names" do
    assert_raises ArgumentError do
      Asset::SyncStatus.set(:wat, :wat)
    end
  end
end
