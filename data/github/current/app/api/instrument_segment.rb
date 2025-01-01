# typed: false
# frozen_string_literal: true

module Api::InstrumentSegment
  # use `include Api::InstrumentSegment::SinatraHooks` to add this to `Api::App`
  module SinatraHooks

    def self.included(child_class)
      child_class.prepend(MethodWrappers)
    end

    module MethodWrappers
      def deliver(*args)
        # build this array then pass it in
        # so that it can be modified inside the block
        tags = []
        Api::InstrumentSegment.call(env, "api.request.deliver", tags: tags) do
          result = super(*args)
          if GitHub.flipper[:api_deliver_include_serializer_method].enabled?
            if args.first == :raw
              tags << "serializer_method:raw"
            else
              tags << "serializer_method:other"
            end
          end
          tags << "response_status:#{status.inspect}"
          result
        end
      end

      def ensure_request_is_within_rate_limit!
        super
      end

      def access_allowed?(...)
        # This is passed in, _then_ modified, so that datadog will
        # get a tag from _inside_ the block.
        tags = []
        Api::InstrumentSegment.call(env, "api.request.access_allowed", tags: tags) do
          result = super(...)
          tags << "authorized:#{result.inspect}"
          result
        end
      end
    end
  end

  # Raised when a segment is ended before it's started
  class SegmentStateError < StandardError
  end

  class << self
    # @return [Boolean] True if `segment_name` was started and has not been ended yet
    def active?(env, segment_name)
      !!env["api.instrument_segment"]&.key?(segment_name)
    end

    # Start tracking a segment named `segment_name`.
    #
    # This method is a no-op if the flag is not enabled for this request.
    #
    # @param env [Hash] A Rack env
    # @param segment_name [String] A name for the datadog stat
    # @return [void]
    def begin_segment(env, segment_name)
      prepare_storage(env)
      env["api.instrument_segment"][segment_name] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Record the duration for `segment_name` and remove its tracking info.
    # This method raises if `segment_name` wasn't started with `begin_segment`.
    #
    # This method is a no-op if the flag is not enabled for this request.
    #
    # @param env [Hash] A Rack env
    # @param segment_name [String] A name for the datadog stat, matches a `begin_segment` segment name
    # @param tags [Array<String>] Extra tags for the datadog stat
    # @return [void]
    def end_segment(env, segment_name, tags: [])
      prepare_storage(env)
      started_at = env["api.instrument_segment"].delete(segment_name)
      if started_at.nil?
        raise SegmentStateError, "Can't end un-started segment: #{segment_name.inspect} (active segments: #{env["api.instrument_segment"].keys.select { |k| k.is_a?(String) }}))"
      end
      elapsed_ms = 1000.0 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at)
      record_stat(env, segment_name, elapsed_ms, tags: tags)
    end

    # Run the given block and record the duration as `segment_name`.
    #
    # This method is a no-op if the flag is not enabled for this request.
    #
    # @param env [Hash] A Rack env
    # @param segment_name [String] A datadog stat name
    # @param tags [Array<String>] Extra tags for the datadog stat
    # @return [Object] The return value of the given block
    def call(env, segment_name, tags: [], &block)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      GitHub.tracer.in_span(segment_name, kind: :client) do
        block.call
      end
    ensure
      finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed_ms = (finished_at - started_at) * 1000.0
      prepare_storage(env)
      record_stat(env, segment_name, elapsed_ms, tags: tags)
    end

    private

    # This method is called before any other operations;
    # it prepares a hash that `.begin_segment` and `.end_segment` depend on.
    def prepare_storage(env)
      env["api.instrument_segment"] ||= { tags: nil }
    end

    def record_stat(env, segment_name, elapsed_ms, tags:)
      default_tags = env["api.instrument_segment"][:tags] ||= [
        "http_method:#{env['REQUEST_METHOD']}",
        "api_app:#{env["process.api.controller"]}",
      ]

      # This value becomes available once Sinatra takes over the request.
      # (It's not there when the router first picks a Sinatra app.)
      if default_tags.size == 2 && (route_pattern = Api::App.route_pattern(env))
        default_tags << "route_pattern:#{route_pattern}"
        default_tags.freeze
      end

      GitHub.dogstats.distribution(segment_name, elapsed_ms, tags: tags + default_tags)
    end
  end
end
