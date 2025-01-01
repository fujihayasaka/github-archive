# typed: true
# frozen_string_literal: true

require "test_helper"

class HovercardContextsBaseTest < GitHub::TestCase
  setup do
    @instance = Hovercard::Contexts::Base.new
  end

  context ".hovercard_sentence" do
    test "with one entry just returns that entry" do
      assert_equal "one", @instance.hovercard_sentence(["one"], max: 10)
    end

    test "with less than max entries returns all as a sentence" do
      assert_equal "one, two, and three", @instance.hovercard_sentence(%w[one two three], max: 10)
    end

    test "with more than max entries returns a shortened sentence" do
      assert_equal "one and 2 more", @instance.hovercard_sentence(%w[one two three], max: 2)
    end

    test "with max or one more than max entries, refuses to show 'and 1 more'" do
      assert_equal "one, two, and three", @instance.hovercard_sentence(%w[one two three], max: 3)
      assert_equal "one, two, and 2 more", @instance.hovercard_sentence(%w[one two three four], max: 3)
    end

    test "allows passing in a total that is larger than collection.count" do
      assert_equal "one, two, and 40 more", @instance.hovercard_sentence(%w[one two three], max: 3, total: 42)
    end

    test "allows passing less than max elements if total is supplied" do
      assert_equal "one and 41 more", @instance.hovercard_sentence(["one"], max: 3, total: 42)
    end

    test "allows a formatting block to be optionally passed" do
      assert_equal "john, john, and john", @instance.hovercard_sentence([1, 2, 3], max: 3) { "john" }
    end
  end
end
