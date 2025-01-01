# frozen_string_literal: true
# typed: true

require "test_helper"
require "vexi/instrumentation_context"

class Vexi::InstrumentationContextTest < Minitest::Test

  describe Vexi::InstrumentationContext do
    before do
      @context = T.let(Vexi::InstrumentationContext.new, Vexi::InstrumentationContext)
    end

    describe "#instrument_timing" do
      it "returns the result of the passed block" do
        expected_result = "some_result"

        result = @context.instrument_timing(:"test.is_enabled", properties: { feature_name: "feature" }) do
          expected_result
        end

        assert_equal expected_result, result
      end

      it "instruments a duration event and passes the correct context" do
        time_sequence = sequence("time_sequence")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(finish)

        @context.instrument_timing(:"test.is_enabled", properties: { feature_name: "feature" }) do
          "some result"
        end

        assert_equal({ "test.is_enabled": {
          feature_name: "feature",
          measured_start: start,
          measured_finish: finish,
        }}, @context.to_h)
      end

      it "allows adding metadata to the context from the passed block" do
        time_sequence = sequence("time_sequence")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(finish)

        @context.instrument_timing(:"test.is_enabled", properties: { feature_name: "feature" }) do |context|
          context[:item_count] = 1337
          context[:boolean_flag] = true

          "some result"
        end

        assert_equal({ "test.is_enabled": {
          feature_name: "feature",
          measured_start: start,
          measured_finish: finish,
          item_count: 1337,
          boolean_flag: true,
        }}, @context.to_h)
      end

      it "records a duration event when the calling block returns early" do
        time_sequence = sequence("time_sequence")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(time_sequence).returns(finish)

        # This needs to be wrapped in a method to test the early return,
        # it would otherwise return from the test
        def execute
          @context.instrument_timing(:"test.is_enabled", properties: { feature_name: "feature" }) do
            return "some value"
          end
        end
        execute

        assert_equal({ "test.is_enabled": {
          feature_name: "feature",
          measured_start: start,
          measured_finish: finish,
        }}, @context.to_h)
      end
    end

    describe "#instrument_error" do
      it "records an error event and includes the correct properties" do
        message = "boom"
        error = StandardError.new(message)

        @context.instrument_error(:test_error, error, message: message, properties: { feature_name: "feature" })

        assert_equal({
          test_error: {
            error: error,
            message: message,
            feature_name: "feature",
          }
        }, @context.to_h)
      end
    end

    describe "#[]" do
      it "sets the context property in the store" do
        property = :my_property
        @context[property] = "my value"

        assert_equal("my value", @context.to_h[property])
      end
    end

    describe "#[]" do
      it "gets a context property from the store" do
        value = "value"
        @context[:property] = value

        assert_equal(value, @context[:property])
      end
    end
  end
end
