# typed: true
# frozen_string_literal: true

require "test_helper"

class TestCoderAdds2
  def dump(v)
    v + 2
  end

  def load(v)
    v - 2
  end
end

class TestCoderReturnsEmpty
  def load(_)
    " "
  end
end

class CodersDefaultTest < GitHub::TestCase
  context "#dump" do
    test "delegates to wrapped coder" do
      assert_equal 4, Coders::Default.new(TestCoderAdds2.new, :default_val).dump(2)
    end
  end

  context "#load" do
    context "when serialized value is present" do
      test "delegates to wrapped coder" do
        assert_equal 2, Coders::Default.new(TestCoderAdds2.new, :default_val).load(4)
      end

      context "but deserialized value is blank" do
        test "returns pre-configured default" do
          assert_equal :default_val, Coders::Default.new(TestCoderReturnsEmpty.new, :default_val).load(:foo)
        end

        test "dups the default value to prevent shared mutable state" do
          coder = Coders::Default.new(TestCoderReturnsEmpty.new, [])

          loaded = coder.load(:foo)
          assert_equal [], loaded

          loaded.push :stuff
          assert_equal [], coder.load(:foo)
        end
      end
    end

    context "when serialized value is blank" do
      test "returns pre-configured default" do
        coder = nil # would blow up if .load is invoked on it
        assert_equal :default_val, Coders::Default.new(coder, :default_val).load(nil)
      end

      test "dups the default value to prevent shared mutable state" do
        coder = Coders::Default.new(Coders::Identity.new, [])

        loaded = coder.load(nil)
        assert_equal [], loaded

        loaded.push :stuff
        assert_equal [], coder.load(nil)
      end
    end
  end
end
