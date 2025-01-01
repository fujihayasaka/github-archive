# frozen_string_literal: true
# typed: true

require "timecop"

require "test_helper"
require "vexi/notifications"
require "vexi/instrumentation_context"

class NotificationsTest < Minitest::Test
  describe "Notifications" do
    before do
      @instrumenter = mock
      @original_instrumenter = Vexi::Notifications.instrumenter
      Vexi::Notifications.instrumenter = @instrumenter

      @configuration_context = {
        version: "0.1.1",
        adapter: "test",
        cache: "none",
      }
    end

    after do
      Vexi::Notifications.instrumenter = @original_instrumenter
      Vexi::Notifications.configuration_context = {}
    end

    describe "#instrument_error" do
      it "instruments an error event and passes the correct context" do
        message = "boom"
        error = StandardError.new(message)

        Vexi::Notifications.configuration_context = {}

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.error", {
          config: {},
          operation: "test.is_enabled",
          message: message,
          error: error,
          feature_name: "feature",
        })

        Vexi::Notifications.instrument_error("test.is_enabled", error, message: message, context: { feature_name: "feature" })
      end

      it "applies the configuration context and adds it to the notification" do
        message = "boom"
        error = StandardError.new(message)

        Vexi::Notifications.configuration_context = @configuration_context

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.error", {
          config: @configuration_context,
          operation: "test.is_enabled",
          message: message,
          error: error,
          feature_name: "feature",
        })

        Vexi::Notifications.instrument_error("test.is_enabled", error, message: message, context: { feature_name: "feature" })
      end
    end

    describe "#instrument_timing" do
      it "returns the result of the passed block" do
        expected_result = "some_result"

        @instrumenter.stubs(:instrument)

        result = Vexi::Notifications.instrument_timing("test.is_enabled", properties: { feature_name: "feature" }) do
          expected_result
        end

        assert_equal expected_result, result
      end

      it "instruments a duration event and passes the correct context" do
        monotonic_time = sequence("monotonic_time")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(finish)

        Vexi::Notifications.configuration_context = {}

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.duration", {
          config: {},
          operation: "test.is_enabled",
          measured_start: start,
          measured_finish: finish,
          feature_name: "feature",
        })

        Vexi::Notifications.instrument_timing("test.is_enabled", properties: { feature_name: "feature" }) do
          "some result"
        end
      end

      it "allows adding metadata to the context from the passed block" do
        monotonic_time = sequence("monotonic_time")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(finish)

        Vexi::Notifications.configuration_context = {}

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.duration", {
          config: {},
          operation: "test.is_enabled",
          measured_start: start,
          measured_finish: finish,
          feature_name: "feature",
          item_count: 1337,
          boolean_flag: true,
        })

        Vexi::Notifications.instrument_timing("test.is_enabled", properties: { feature_name: "feature" }) do |context|
          context[:item_count] = 1337
          context[:boolean_flag] = true

          "some result"
        end
      end

      it "instruments a duration event when the calling block returns early" do
        monotonic_time = sequence("monotonic_time")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(finish)

        Vexi::Notifications.configuration_context = {}

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.duration", {
          config: {},
          operation: "test.is_enabled",
          measured_start: start,
          measured_finish: finish,
          feature_name: "feature",
        })

        Vexi::Notifications.instrument_timing("test.is_enabled", properties: { feature_name: "feature" }) do
          "some result"
        end
      end

      it "applies the configuration context and adds it to the notification" do
        monotonic_time = sequence("monotonic_time")

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(start)
        Process.expects(:clock_gettime).with(Process::CLOCK_MONOTONIC).in_sequence(monotonic_time).returns(finish)

        Vexi::Notifications.configuration_context = @configuration_context

        @instrumenter.expects(:instrument).with("vexi.test.is_enabled.duration", {
          config: @configuration_context,
          operation: "test.is_enabled",
          measured_start: start,
          measured_finish: finish,
          feature_name: "feature",
        })

        Vexi::Notifications.instrument_timing("test.is_enabled", properties: { feature_name: "feature" }) do
          "some result"
        end
      end
    end
  end
end
