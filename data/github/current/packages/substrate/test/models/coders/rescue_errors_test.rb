# typed: true
# frozen_string_literal: true

require "test_helper"

class TestCoderThrows
  Error = Class.new(StandardError)
  OtherError = Class.new(StandardError)

  attr_accessor :raises # control which type of exception to raise

  def initialize
    @raises = Error # error to raise by default
  end

  def dump(*)
    "dumped"
  end

  def load(*)
    raise @raises, "error loading"
  end
end

class CodersRescueErrorsTest < GitHub::TestCase
  setup do
    @wrapped_coder = TestCoderThrows.new
  end

  context "#dump" do
    test "delegates to wrapped coder" do
      assert_equal "dumped", Coders::RescueErrors.new(@wrapped_coder).dump(:stuff)
    end
  end

  context "#load" do
    context "when not given errors to rescue" do
      test "defaults to rescuing StandardError types" do
        coder = Coders::RescueErrors.new(@wrapped_coder)
        @wrapped_coder.raises = StandardError

        coder.load(:stuff) # does not raise
      end

      test "does not rescue Exception types" do
        coder = Coders::RescueErrors.new(@wrapped_coder)
        @wrapped_coder.raises = Exception

        assert_raises(Exception) { coder.load(:stuff) }
      end
    end

    test "rescues expected exceptions from wrapped coder" do
      coder = Coders::RescueErrors.new(@wrapped_coder, TestCoderThrows::Error)

      coder.load(:stuff) # does not raise
    end

    test "rescues multiple exception types" do
      coder = Coders::RescueErrors.new @wrapped_coder, [
        TestCoderThrows::Error,
        TestCoderThrows::OtherError,
      ]

      coder.load(:stuff) # does not raise
    end

    test "does not rescue unexpected exceptions" do
      coder = Coders::RescueErrors.new(@wrapped_coder, TestCoderThrows::Error)
      @wrapped_coder.raises = TestCoderThrows::OtherError

      assert_raises(TestCoderThrows::OtherError) { coder.load(:stuff) }
    end

    context "when rescuing errors" do
      test "invokes the given handler with the error, encoded value, and coder" do
        block_called = T.let(false, T::Boolean)

        coder = Coders::RescueErrors.new @wrapped_coder do |error, value, coder|
          block_called = true

          assert error.is_a?(TestCoderThrows::Error)
          assert_equal :stuff, value
          assert_equal @wrapped_coder, coder
        end

        coder.load(:stuff)
        assert block_called
      end

      test "returns the handler's return value" do
        coder = Coders::RescueErrors.new(@wrapped_coder) { :dummy_return }

        assert_equal :dummy_return, coder.load(:stuff)
      end

      test "returns nil if no handler" do
        coder = Coders::RescueErrors.new @wrapped_coder

        assert_nil coder.load(:stuff)
      end
    end

    context "when explicitly given no errors to rescue" do
      test "as nil, will not rescue anything at all" do
        coder = Coders::RescueErrors.new(@wrapped_coder, nil)
        assert_raises(TestCoderThrows::Error) { coder.load(:stuff) }
      end

      test "as empty array, will not rescue anything at all" do
        coder = Coders::RescueErrors.new(@wrapped_coder, [])
        assert_raises(TestCoderThrows::Error) { coder.load(:stuff) }
      end
    end

    context "when wrapped coder doesn't raise" do
      test "delegates through to wrapped coder" do
        coder = Coders::RescueErrors.new(Coders::Identity.new) { :handled_error }

        assert_equal :stuff, coder.load(:stuff)
      end
    end
  end
end
