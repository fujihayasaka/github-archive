# typed: false
# frozen_string_literal: true

require "test_helper"

class ConditionalAccessResultTest < GitHub::TestCase
  setup do
    @result = ConditionalAccess::Result::new(:r, Hash[
      :a, :unsatisfied,
      :b, :satisfied,
      :c, :inapplicable,
      :d, :unenforceable,
      :e, :unsatisfied,
      :f, :satisfied,
      :g, :inapplicable,
      :h, :unenforceable])
  end

  context "constructor" do
    test "raises on nil resource" do
      e = assert_raises ArgumentError do
        ConditionalAccess::Result::new(nil, Hash[])
      end
      assert_equal "resource cannot be nil", e.message
    end

    test "raises on empty policies hash" do
      e = assert_raises ArgumentError do
        ConditionalAccess::Result::new(:a, Hash[])
      end
      assert_equal "the policies hash cannot be empty", e.message
    end
  end

  Hash[
    :unsatisfied, [:a, :e],
    :satisfied, [:b, :f],
    :inapplicable, [:c, :g],
    :unenforceable, [:d, :h]
  ].each do |outcome, expected|
    test "can get list of #{outcome} policies" do
      assert_equal expected, @result.send(outcome.to_sym)
    end
  end

  test "can get list of authorized policies" do
    assert_equal [:b, :c, :d, :f, :g, :h], @result.authorized
  end
end
