# typed: true
# frozen_string_literal: true

module Audit
  module Test
    class Service < Audit::Service
      attr_reader :captured_events

      # Captures an internal Array of Audit events logged during the execution
      # of a required block. The internal array is not reset between captures
      # to facilitate capturing multiple times and viewing captured events
      # afterwards in a test.
      def capturing_logged_events(only: nil)
        raise ArgumentError, "A block is required" unless block_given?
        @capturing = true
        @capture_only = Array.wrap(only)
        @captured_events = []
        yield
      ensure
        @capturing = false
        @capture_only = []
      end

      # Overrides and calls Audit::Service#log_payload. Intercept logged events
      # to keep a local reference if @capturing is true.
      def log_payload(action:, payload:, on_error_behavior: nil)
        @captured_events ||= []

        if @capturing && (@capture_only.blank? || @capture_only.include?(action))
          @captured_events << payload
        end

        super
      end

      def inline?
        true # Always inline calls when going through this test service.
      end
    end
  end
end
