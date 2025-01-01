# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class KVTest < GitHub::TestCase
    context ".store" do
      test "returns a GitHub::KV instance" do
        assert_nothing_raised do
          assert_instance_of GitHub::KV, SecurityProductsEnablement::KV.store
        end
      end
    end

    context "single key methods" do
      test "sets and gets values" do
        assert_nothing_raised do
          SecurityProductsEnablement::KV.set("services.dependency_graph.enabled", "true")
          assert_equal "true", SecurityProductsEnablement::KV.get("services.dependency_graph.enabled").value!
        end
      end

      test ".set allows an optional expires timestamp" do
        assert_nothing_raised do
          SecurityProductsEnablement::KV.set("later", "gator", expires: 1.minute.from_now)
          assert_equal "gator", SecurityProductsEnablement::KV.get("later").value!
        end
      end

      test "increments keys" do
        SecurityProductsEnablement::KV.increment("my_new_key")
        assert_equal "1", SecurityProductsEnablement::KV.get("my_new_key").value!

        SecurityProductsEnablement::KV.increment("my_new_key")
        assert_equal "2", SecurityProductsEnablement::KV.get("my_new_key").value!
      end

      test "increments keys by a certain amount" do
        SecurityProductsEnablement::KV.increment("by_five", amount: 5)
        assert_equal "5", SecurityProductsEnablement::KV.get("by_five").value!

        SecurityProductsEnablement::KV.increment("by_five", amount: 5)
        assert_equal "10", SecurityProductsEnablement::KV.get("by_five").value!
      end

      test "deletes keys" do
        # Set an validate key exists:
        SecurityProductsEnablement::KV.set("delete_me", "bye!")
        assert_equal "bye!", SecurityProductsEnablement::KV.get("delete_me").value!

        # Delete it and validate it's gone:
        SecurityProductsEnablement::KV.del("delete_me")
        assert_nil SecurityProductsEnablement::KV.get("delete_me").value!
      end

      test "returns if keys exist" do
        SecurityProductsEnablement::KV.set("i_exist", "that's deep, lol.")
        assert SecurityProductsEnablement::KV.exists("i_exist").value!
        refute SecurityProductsEnablement::KV.exists("i_dont_exist").value!
      end

      test ".setnx sets a key if it doesn't already exist" do
        assert SecurityProductsEnablement::KV.setnx("i_exist", "that's deep, lol.")
        refute SecurityProductsEnablement::KV.setnx("i_exist", "this won't be saved!")
      end
    end

    context "multiple key methods" do
      test ".mset and .mget work with multiple values" do
        assert_nothing_raised do
          SecurityProductsEnablement::KV.mset({ "this" => "that", "the" => "other" })
          assert_equal %w(that other), SecurityProductsEnablement::KV.mget(%w(this the)).value!
        end
      end

      test ".mset allows you to set multiple values with an expires timestamp" do
        assert_nothing_raised do
          expires_at = 1.minute.from_now.round.to_time
          SecurityProductsEnablement::KV.mset({ "key1" => "1", "key2" => "2" }, expires: expires_at)

          assert_equal %w(1 2), SecurityProductsEnablement::KV.mget(%w(key1 key2)).value!
          assert_equal [expires_at, expires_at], SecurityProductsEnablement::KV.mttl(%w(key1 key2)).value!
        end
      end

      test ".mexists allows you to check existence of multiple keys" do
        SecurityProductsEnablement::KV.set("exists", "sure does!")
        assert_equal [true, false], SecurityProductsEnablement::KV.mexists(%w(exists doesnt)).value!
      end

      test ".mdel deletes multiple keys" do
        keys = %w(hello world)
        SecurityProductsEnablement::KV.mset({ "hello" => "world", "world" => "is beautiful" })
        SecurityProductsEnablement::KV.mdel(keys)
        assert_equal [false, false], SecurityProductsEnablement::KV.mexists(keys).value!
      end
    end
  end
end
