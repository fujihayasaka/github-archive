# typed: true
# frozen_string_literal: true

require "test_helper"

class Memex::KVTest < GitHub::TestCase
  fixtures do
    @keyname = "memex-kv-test-key"
  end

  test "it doesn't raise any errors on setting a value" do
    assert_nothing_raised do
      Memex::KV.store.set(@keyname, "foo")
    end
  end

  test "it doesn't raise any errors on setting a value with an expiry" do
    assert_nothing_raised do
      Memex::KV.store.set(@keyname, "foo", expires: (Date.today + 1).to_time)
    end
  end

  test "it can successfully read a value" do
    Memex::KV.store.set(@keyname, "foo")

    assert_equal true, Memex::KV.store.exists(@keyname).value { false }
    assert_equal "foo", Memex::KV.store.get(@keyname).value { false }
  end

  test "it does not return the value of an expired key" do
    Memex::KV.store.set(@keyname, "foo", expires: 1.hour.ago)

    refute Memex::KV.store.exists(@keyname).value { false }
    assert_nil Memex::KV.store.get(@keyname).value { false }
  end

  test "it doesn't raise any errors on deleting a value" do
    Memex::KV.store.set(@keyname, "foo")

    assert_nothing_raised do
      Memex::KV.store.del(@keyname)
    end

    refute Memex::KV.store.exists(@keyname).value { false }
  end
end
