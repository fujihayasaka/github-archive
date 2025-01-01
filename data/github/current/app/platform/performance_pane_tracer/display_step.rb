# typed: false
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # This backs the tree view on the staff bar.
    # `DisplayQuery` is the root node, it represents the query as a whole.
    # `DisplayStep` represents a field in the query, roughly.
    #
    # (Some high-level phases in the query are also wrapped in `DisplayStep`.)
    #
    # In a list, all objects in the list _share_ a node (list indexes are ignored).
    #
    # Nodes are initialized empty, then built up by `DisplayQuery`.
    # When `DisplayQuery` is done with _all_ the timings, it calls `#freeze_stats`
    # on its children to freeze the whole tree.
    #
    # It's rendered into `app/views/site/_graphql_stats_step.html.erb`
    class DisplayStep
      def initialize(name:, path:, timings: [])
        @path = path
        @name = name
        @children = {}
        @timings = timings
      end

      # @return [Array<Platform::Tracer::StepTiming>] Timed events that compose this node
      attr_reader :timings

      # @return [Hash<String => DisplayStep] Subselections on this field, if there are any
      attr_reader :children

      # @return [String] The name of this field in the GraphQL response
      attr_reader :name

      # @return [Array<String>] The names of nodes leading to this node (like `path` in error messages, but excluding list indexes)
      attr_reader :path

      # Object fields which were called at this `path`
      # (may be multiple if a field returned Union/Interface)
      # @return [Array<String>]
      attr_reader :names

      # Number of times this field was called
      # (can be greater than 1 when a parent field returned a list)
      # @return [Integer]
      attr_reader :count

      # - own_* methods are for this field _only_, summed for all calls
      # - total_* methods are for this field and all children, summed for all calls
      # - avg_* methods are for this field and all children, averaged over all calls
      # - chidren_* methods are the sum for this fields

      # Timings
      attr_reader :own_ms, :total_ms, :avg_ms, :children_ms
      attr_reader :own_cpu_ms

      # Ruby objects
      attr_reader :own_allocated_objects
      # If profiling enabled, one of these will have stuff:
      attr_reader :profile_lines, :profile_objects

      # External calls
      [:gitrpc_calls, :mysql_calls, :redis_calls, :elastomer_calls, :mysql_cache_hits].each do |call_type|
        attr_reader "own_#{call_type}_count", "own_#{call_type}_ms", "own_#{call_type}"
      end
      # We only have aggregates here:
      attr_reader :own_memcached_calls_count, :own_memcached_calls_ms

      # Calculate everything, then freeze.
      # Trying to make as few iterations as we can here, since this really adds up.
      def freeze_stats
        @names = []
        @count = 0
        @own_ms = 0
        @own_cpu_ms = 0
        @own_allocated_objects = 0

        @own_memcached_calls_count = 0
        @own_memcached_calls_ms = 0
        @own_mysql_calls = []
        @own_redis_calls = []
        @own_gitrpc_calls = []
        @own_elastomer_calls = []
        @own_mysql_cache_hits = []
        @profile_lines = []
        @profile_objects = nil
        @profile_lines = nil

        timings.each do |t|
          if !t.lazy?
            @names << t.name
            # Only count eager times; promise times are duplicate
            @count += 1
          end
          @own_ms += (t.duration * 1000)
          @own_cpu_ms += (t.cpu_time * 1000)
          @own_allocated_objects += t.allocated_objects_count
          @own_mysql_calls.concat(t.mysql_calls)
          @own_redis_calls.concat(t.redis_calls)
          @own_gitrpc_calls.concat(t.gitrpc_calls)
          @own_mysql_cache_hits.concat(t.mysql_cache_hits)
          @own_elastomer_calls.concat(t.elastomer_calls)
          @own_memcached_calls_ms += t.memcached_calls_time * 1000
          @own_memcached_calls_count += t.memcached_calls_count
          # Merge allocated objects hashes:
          t.allocated_objects.each do |class_name, counts|
            @profile_objects ||= Hash.new { |h, k| h[k] = { count: 0, lines: Hash.new(0) } }
            @profile_objects[class_name][:count] += counts[:count]
            counts[:lines].each do |line, count|
              @profile_objects[class_name][:lines][line] += count
            end
          end
          # Merge rblineprof results:
          file_lines = nil
          t.lines.each do |filepath, file_lines|
            # { filename => { lineidx => lineprof }}
            @profile_lines ||= Hash.new { |h, k| h[k] = {} }
            file_bodies ||= Hash.new do |h, k|
              h[k] = begin
                File.read(k).split("\n")
              rescue Errno::ENOENT
                EVAL_LINES
              end
            end
            agg_file_lines = @profile_lines[filepath]
            file_body = nil
            file_lines.each_with_index do |(wall, cpu, calls, allocations), idx|
              if calls == 0 || idx == 0
                next
              end
              line = agg_file_lines[idx]
              if line.nil?
                file_body ||= file_bodies[filepath]
                line = agg_file_lines[idx] = [0, 0, 0, 0, filepath, idx - 1, file_body[idx - 1]]
              end
              line[0] += wall
              line[1] += cpu
              line[2] += calls
              line[3] += allocations
            end
          end
        end

        @profile_objects ||= Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE
        @profile_lines ||= Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE
        @own_mysql_calls_count = @own_mysql_calls.size
        @own_mysql_calls_ms = @own_mysql_calls.sum(&:duration) * 1000

        @own_mysql_cache_hits_count = @own_mysql_cache_hits.size
        @own_mysql_cache_hits_ms = 0

        @own_redis_calls_count = @own_redis_calls.size
        @own_redis_calls_ms = @own_redis_calls.sum(&:duration)

        @own_gitrpc_calls_count = @own_gitrpc_calls.size
        @own_gitrpc_calls_ms = @own_gitrpc_calls.sum(&:duration)

        @own_elastomer_calls_count = @own_elastomer_calls.size
        @own_elastomer_calls_ms = @own_elastomer_calls.sum(&:time)

        @names.uniq!
        @children_ms = 0
        @children.each_value do |child|
          child.freeze_stats
          @children_ms += child.total_ms
        end
        @total_ms = @children_ms + @own_ms

        if @count > 1
          # @count can be zero, too, if parsing didnt happen, for example
          @avg_ms = @total_ms / @count
        else
          @avg_ms = @total_ms
        end

        # Now, we should be done preparing internal state, so lock out later changes
        @children.freeze
        @timings.freeze
        freeze
      end

      # Used when a source line of code doesn't exist
      EVAL_LINES = Hash.new { |h, k| h[k] = "(eval:#{k})" }
    end
  end
end
