# typed: true
# frozen_string_literal: true

require "test_helper"

class CodersIdentityTest < GitHub::TestCase
  test "#dump returns the given value" do
    assert_equal 5, Coders::Identity.new.dump(5)
  end

  test "#load returns the given value" do
    assert_equal 7, Coders::Identity.new.load(7)
  end
end
