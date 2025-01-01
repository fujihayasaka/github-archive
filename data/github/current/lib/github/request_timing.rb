# typed: strict
# frozen_string_literal: true

module GitHub
  # Public: A class for tracking performance of operations within a request.
  #
  # The goal is to answer "where is time being spent?" for a given
  # controller/action so you can prioritize performance optimizations.
  #
  # For example, if you have a controller action that takes 500ms p50,
  # and you want to know how that 500ms breaks down into logical categories,
  # you can use this to track the time spent in each category.
  #
  # The categories are not automatically inferred - you have to explicitly
  # track them using the #track method.
  class RequestTiming
    extend T::Sig

    sig { params(common_tags: T::Hash[Symbol, T.untyped]).void }
    def initialize(common_tags: {})
      @tags = T.let([], T::Array[String])
      common_tags.each do |k, v|
        @tags << "#{k}:#{v}"
      end
      @operation_timings = T.let(Hash.new(0), T::Hash[Symbol, Integer])
    end

    sig { void }
    def start_controller_action
      @controller_start_time = T.let(GitHub::Dogstats.monotonic_time, T.nilable(Float))
    end

    sig { void }
    def finish_controller_action
      return if @controller_start_time.nil?
      elapsed = GitHub::Dogstats.duration(@controller_start_time)

      # If no operations were tracked, don't emit any metrics
      return if @operation_timings.empty?

      # One metric for whole request
      GitHub.dogstats.distribution(
        "request_timing.controller_action",
        elapsed,
        tags: @tags,
      )

      # One metric per operation within the request
      @operation_timings.each do |operation, duration|
        GitHub.dogstats.distribution(
          "request_timing.operation",
          duration,
          tags: @tags + ["operation:#{operation}"],
        )
      end
    end

    # Public: Track the time spent in the given operation. This
    # won't do anything unless you call RequestTiming#instrument_controller_action
    # around the controller action.
    #
    # operation - The operation to track.
    #
    # Returns the result of the block.
    #
    # Examples
    #
    #   metrics = GitHub::RequestTiming.new
    #   @discussions = metrics.track(:load_discussions) do
    #     load_discussions
    #   end
    #
    #   metrics.track(:load_discussion_bodies) do
    #     load_discussion_bodies
    #   end
    #
    #   @discussions.each do |discussion|
    #     # Subsequent operations with the same name will be
    #     # summed together and published as a single metric for
    #     # the whole request.
    #     #
    #     # In this case, a single metric will be emitted that looks like:
    #     # `request_timing.operation{operation:load_discussion_comments}`
    #     metrics.track(:load_discussion_comments) do
    #       discussion.load_discussion_comments
    #     end
    #   end
    sig { params(operation: Symbol, blk: T.proc.returns(T.untyped)).returns(T.untyped) }
    def track(operation, &blk)
      start_time = GitHub::Dogstats.monotonic_time
      result = yield
      elapsed = GitHub::Dogstats.duration(start_time)
      @operation_timings[operation] = T.must(@operation_timings[operation]) + elapsed
      result
    end

    # Public: Add a hash of tags that will be applied to all request metrics emitted during #instrument_controller_action.
    sig { params(new_tags: T::Hash[Symbol, T.untyped]).void }
    def add_tags(new_tags)
      new_tags.each do |k, v|
        @tags << "#{k}:#{v}"
      end
    end
  end
end
