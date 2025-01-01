# typed: true
# frozen_string_literal: true

require "test_helper"

class TestCoderAdds1
  def dump(v)
    v + 1
  end

  def load(v)
    v - 1
  end
end

class TestCoderMultiplies2
  def dump(v)
    v * 2
  end

  def load(v)
    v / 2
  end
end

class CodersComposedTest < GitHub::TestCase
  test "composes coders' dump methods left to right" do
    composed = Coders::Composed.new([TestCoderAdds1.new, TestCoderMultiplies2.new])

    assert_equal 10, composed.dump(4)
  end

  test "composes coders' load methods right to left" do
    composed = Coders::Composed.new([TestCoderAdds1.new, TestCoderMultiplies2.new])

    assert_equal 4, composed.load(10)
  end
end
