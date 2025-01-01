# frozen_string_literal: true
# typed: strict

module Vexi
  # Circuit breaker configuration options.
  class CircuitBreakerConfig
    extend T::Sig
    extend T::Helpers

    sig { returns(T::Boolean) }
    attr_accessor :force_open

    sig { returns(T::Boolean) }
    attr_accessor :force_closed

    sig { returns(Integer) }
    attr_accessor :sleep_window_seconds

    sig { returns(Integer) }
    attr_accessor :request_volume_threshold

    sig { returns(Integer) }
    attr_accessor :error_threshold_percentage

    sig { returns(Integer) }
    attr_accessor :window_size_in_seconds

    sig { returns(Integer) }
    attr_accessor :bucket_size_in_seconds

    sig {
      params(
        force_open: T::Boolean,
        force_closed: T::Boolean,
        sleep_window_seconds: Integer,
        request_volume_threshold: Integer,
        error_threshold_percentage: Integer,
        window_size_in_seconds: Integer,
        bucket_size_in_seconds: Integer
      ).void
    }
    def initialize(
      force_open: false,
      force_closed: false,
      sleep_window_seconds: 5,
      request_volume_threshold: 20,
      error_threshold_percentage: 50,
      window_size_in_seconds: 60,
      bucket_size_in_seconds: 10);
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h; end
  end
end
