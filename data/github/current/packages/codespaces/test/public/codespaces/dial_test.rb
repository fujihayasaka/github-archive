# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesDialTest < GitHub::TestCase

  class FakeDial < Codespaces::Dial
    def key
      "fake_dial"
    end

    def default_value
      "default"
    end

    def description
      "description"
    end
  end

  test "initialize" do
    dial = FakeDial.new
    assert_equal dial.key, "fake_dial"
    assert_equal dial.default_value, "default"
    assert_equal dial.description, "description"
    assert_equal dial.value, "default"
  end

  test "value is cached" do
    with_cache_enabled do
      new_value = "new_value"
      Codespaces::Kv.store.expects(:get).once.returns(GitHub::Result.new { new_value })
      dial = FakeDial.new
      dial.value = new_value
      dial.save
      dial = FakeDial.new
      assert_equal dial.value, new_value
      dial = FakeDial.new
      assert_equal dial.value, new_value
    end
  end

  test "force cache miss" do
    with_cache_enabled do
      new_value = "new_value"
      Codespaces::Kv.store.expects(:get).twice.returns(GitHub::Result.new { new_value })
      dial = FakeDial.new
      dial.value = new_value
      dial.save
      dial = FakeDial.new
      assert_equal dial.value, new_value
      dial = FakeDial.new(force_cache_miss: true)
      assert_equal dial.value, new_value
    end
  end

end unless GitHub.enterprise?
