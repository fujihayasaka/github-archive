# typed: true
# frozen_string_literal: true

# Note: this file omits type annotations because it is performance critical.

require_relative "../metrics"
require_relative "../storage/process"

module GitHub
  module CircuitBreaker
    module Patch
      # A patch to Resilient::CircuitBreaker::Properties to provide default values specific to GitHub.
      module DefaultProperties
        DEFAULT_WINDOW_SIZE_IN_SECONDS = 60
        DEFAULT_BUCKET_SIZE_IN_SECONDS = 10

        def initialize(options = {})
          return super(options) if options.include?(:metrics)

          window_size_in_seconds = options.fetch(:window_size_in_seconds, DEFAULT_WINDOW_SIZE_IN_SECONDS)
          bucket_size_in_seconds = options.fetch(:bucket_size_in_seconds, DEFAULT_BUCKET_SIZE_IN_SECONDS)

          storage = ::GitHub::CircuitBreaker::Storage::Process.new(
            buckets: window_size_in_seconds / bucket_size_in_seconds,
            bucket_size: bucket_size_in_seconds
          )
          metrics = ::GitHub::CircuitBreaker::Metrics.new(storage: storage)

          super(options.merge(metrics: metrics))
        end
      end
    end
  end
end
