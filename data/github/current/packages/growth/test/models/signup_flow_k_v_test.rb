# typed: true
# frozen_string_literal: true

require "test_helper"

class SignupFlowKVTest < GitHub::TestCase
  context ".store" do
    test "it returns an instance of GitHub::KV" do
      assert_instance_of GitHub::KV, SignupFlowKV.store
    end

    test "it returns the same instance of GitHub::KV on subsequent calls" do
      store1 = SignupFlowKV.store
      store2 = SignupFlowKV.store

      assert_same store1, store2
    end
  end

  context ".build_store" do
    test "it returns an instance of GitHub::KV" do
      assert_instance_of GitHub::KV, SignupFlowKV.build_store
    end

    test "it returns a different instance of GitHub::KV on subsequent calls" do
      store1 = SignupFlowKV.build_store
      store2 = SignupFlowKV.build_store

      refute_same store1, store2
    end

    test "it sets the correct table name in the config" do
      store = SignupFlowKV.build_store
      assert_equal :signup_flow_key_values, store.instance_variable_get(:@table_name)
    end
  end
end
