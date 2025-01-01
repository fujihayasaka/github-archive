# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module Vexi
  class CircuitBreakerConfig
    # allows forcing the circuit open (stopping all requests)
    attr_accessor :force_open

    # allows ignoring errors and therefore never trip "open"
    # (ie. allow all traffic through); normal instrumentation will still
    # happen, thus allowing you to "test" configuration live without impact
    attr_accessor :force_closed

    # seconds after tripping circuit before allowing retry
    attr_accessor :sleep_window_seconds

    # number of requests that must be made within a statistical window before
    # open/close decisions are made using stats
    attr_accessor :request_volume_threshold

    # % of "marks" that must be failed to trip the circuit
    attr_accessor :error_threshold_percentage

    # number of seconds in the statistical window
    attr_accessor :window_size_in_seconds

    # size of buckets in statistical window
    attr_accessor :bucket_size_in_seconds

    def initialize(
      force_open: false,
      force_closed: false,
      sleep_window_seconds: 5,
      request_volume_threshold: 20,
      error_threshold_percentage: 50,
      window_size_in_seconds: 60,
      bucket_size_in_seconds: 10)

      @force_open = T.let(force_open, T::Boolean)
      @force_closed = T.let(force_closed, T::Boolean)
      @sleep_window_seconds = T.let(sleep_window_seconds, Integer)
      @request_volume_threshold = T.let(request_volume_threshold, Integer)
      @error_threshold_percentage = T.let(error_threshold_percentage, Integer)
      @window_size_in_seconds = T.let(window_size_in_seconds, Integer)
      @bucket_size_in_seconds = T.let(bucket_size_in_seconds, Integer)
    end

    def to_h
      {
        force_open: @force_open,
        force_closed: @force_closed,
        sleep_window_seconds: @sleep_window_seconds,
        request_volume_threshold: @request_volume_threshold,
        error_threshold_percentage: @error_threshold_percentage,
        window_size_in_seconds: @window_size_in_seconds,
        bucket_size_in_seconds: @bucket_size_in_seconds
      }
    end
  end
end
