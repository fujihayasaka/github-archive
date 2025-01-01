# typed: true
# frozen_string_literal: true

require "test_helper"

class Growth::KVTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    @repo = create(:public_repository, owner: @user)
    @keyname = "growth-kv-test-key"
  end

  context ".store" do
    test "it returns an instance of GitHub::KV" do
      assert_instance_of GitHub::KV, Growth::KV.store
    end

    test "it returns the same instance of GitHub::KV on subsequent calls" do
      store1 = Growth::KV.store
      store2 = Growth::KV.store

      assert_same store1, store2
    end
  end

  context ".build_store" do
    test "it returns an instance of GitHub::KV" do
      assert_instance_of GitHub::KV, Growth::KV.build_store
    end

    test "it returns a different instance of GitHub::KV on subsequent calls" do
      store1 = Growth::KV.build_store
      store2 = Growth::KV.build_store

      refute_same store1, store2
    end

    test "it sets the correct table name in the config" do
      store = Growth::KV.build_store
      assert_equal :growth_notice_key_values, store.instance_variable_get(:@table_name)
    end
  end
end
