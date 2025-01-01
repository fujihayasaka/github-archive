# typed: true
# frozen_string_literal: true

require "faraday"

require "concurrent_faraday/instrumentation"
require "concurrent_faraday/promise"
require "concurrent_faraday/future_response"
require "concurrent_faraday/threaded_parallel_manager"

require "concurrent_faraday/async_rack_builder"
require "concurrent_faraday/excon_base"
require "concurrent_faraday/concurrent_adapter"

module ConcurrentFaraday
  def self.new(url = nil, options = {}, &block)
    num_threads = options.delete(:num_threads) || 1

    options = ::Faraday::Utils.deep_merge(::Faraday.default_connection_options, options)

    # Give an empty block to the builder, otherwise it will set some default adapters
    builder = ::ConcurrentFaraday::AsyncConnectionRackBuilder.new { |b| b }

    # Set the default parallel manager, to be the thread's one
    parallel_manager = ConcurrentFaraday::ThreadedParallelManager.new(num_threads)

    ::Faraday::Connection.new(url, options.merge(builder: builder, parallel_manager: parallel_manager), &block)
  end
end
