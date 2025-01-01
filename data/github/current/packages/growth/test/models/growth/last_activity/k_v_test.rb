# typed: true
# frozen_string_literal: true

require "test_helper"

class Growth::LastActivityKVTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    @repo = create(:public_repository, owner: @user)
    @keyname = "growth-kv-test-key"
  end

  class GrowthLastActivityKeyValues < ApplicationRecord::Domain::UsersCollab
    self.table_name = "growth_last_activity_key_values"
  end

  context ".store" do
    test "it returns an instance of GitHub::KV" do
      assert_instance_of GitHub::KV, Growth::LastActivity::KV.store
    end

    test "it returns the same instance of GitHub::KV on subsequent calls" do
      store1 = Growth::LastActivity::KV.store
      store2 = Growth::LastActivity::KV.store

      assert_same store1, store2
    end
  end

  context ".build_store" do
    test "it returns an instance of Growth::LastActivity::KV" do
      assert_instance_of GitHub::KV, Growth::LastActivity::KV.build_store
    end

    test "it returns a different instance on subsequent calls" do
      store1 = Growth::LastActivity::KV.build_store
      store2 = Growth::LastActivity::KV.build_store

      refute_same store1, store2
    end

    test "it sets the correct table name in the config" do
      store = Growth::LastActivity::KV.build_store
      assert_equal :growth_last_activity_key_values, store.instance_variable_get(:@table_name)
    end
  end

  test "it writes to target" do
    store = Growth::LastActivity::KV.build_store
    store.set(@keyname, "test", expires: 1.day.from_now)
    assert_equal "test", GrowthLastActivityKeyValues.find_by(key: @keyname).value
    assert_equal "test", store.get(@keyname).value { nil }
  end
end
