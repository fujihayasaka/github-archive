# typed: false
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # `#with_detailed_profile` _may_ wrap the yielded block with fine-grained profiling.
    # This is used for profiling specific GraphQL fields.
    class DetailedProfile
      def initialize(profile_type:, profile_path:)
        case profile_type
        when :lines, :allocations, nil
          @profile_type = profile_type
        else
          raise Platform::Errors::Internal, "Unexpected detailed profile_type: #{profile_type.inspect}"
        end

        @profile_path = profile_path
        # This isn't available when this object is initialized, so
        # it will be assigned later
        @query = nil
        # Set to true if `@profile_path` was matched.
        # If it wasn't matched, maybe you want to add an error to the query.
        @was_profiled = false
      end

      def was_profiled?
        @was_profiled
      end

      attr_writer :query

      # If `field_data` should be profiled, it's wrapped,
      # otherwise, it's called directly, and empty profile results are returned.
      #
      # It returns three values:
      #
      # - The result of the block
      # - The allocation profile result (empty Hash if not profiled)
      # - The lineprof profile result (empty Hash if not profiled)
      #
      # @return [Array(Object, Hash, Hash)]
      def with_detailed_profile(path)
        if @profile_type.nil? || !profile_path?(path)
          result = yield
          [result, Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE, Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE]
        elsif @profile_type == :allocations
          with_allocations { yield }
        elsif @profile_type == :lines
          with_lines { yield }
        end
      end

      private

      # Check whether we want to profile this field or not
      # (checking whether it matches the opt-in profile path).
      def profile_path?(current_path)
        # This can run before `@query` has been assiged (eg, during lexical analysis),
        # skip in that case.
        if @query && @query.selected_operation_name == @profile_path[0]
          # Use an offset of `1` because `@profile_path` has the operation name at the start.
          current_part_idx = 1
          current_path.each do |path_part|
            profile_path_part = @profile_path[current_part_idx]
            # Support list indexes coming in as Strings, eg `"0"`
            if profile_path_part == String(path_part)
              current_part_idx += 1
            elsif path_part.is_a?(Integer)
              # For dotcom views, list indexes are not considered in the profile path
              next
            else
              # We found a mismatch in the path, we 're not profiling this
              return false
            end
          end
          # We checked this without returning early, but did we check _everything_?
          # (Add 1 to account for operation name in `@profile_path`)
          current_part_idx == @profile_path.size
        else
          false
        end
      end

      # Wrap the given block with `rblineprof`
      def with_lines
        result = nil
        lines = lineprof(/./) do
          result = yield
        end
        [result, Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE, lines]
      end

      # Wrap the given block with object allocation tracing,
      # see `ObjectSpace.trace_object_allocations` for Ruby's support for this
      def with_allocations
        # Let's do something funny:
        # - One last GC run, then stop.
        # - We're going to see what objects were introduced during the query
        # - Be sure to restart GC at the right time!
        # This is borrowed from MemoryProfiler::Reporter
        allocated_objects = Hash.new do |h, k|
          h[k] = {
            count: 0,
            lines: Hash.new(0),
          }
        end
        GC.start
        GC.disable
        last_gc_generation = GC.count
        ObjectSpace.trace_object_allocations_start
        begin
          result = yield
        ensure
          ObjectSpace.trace_object_allocations_stop
        end
        ObjectSpace.each_object do |obj|
          next if ObjectSpace.allocation_generation(obj) != last_gc_generation
          name = obj.class.name
          allocated_objects[name][:count] += 1
          line = "#{ObjectSpace.allocation_sourcefile(obj)}:#{ObjectSpace.allocation_sourceline(obj)}"
          allocated_objects[name][:lines][line] += 1
        end
        [result, allocated_objects, Platform::Tracing::Helpers::BaseTraceMethods::NO_PROFILE]
      ensure
        GC.enable
      end
    end
  end
end
