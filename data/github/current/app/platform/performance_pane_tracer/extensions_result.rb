# typed: false
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # Takes a tracer which has been gathering data
    # and uses it to render a Hash which can be returned
    # in the `"extensions"` key of a GraphQL result.
    class ExtensionsResult
      MAX_BACKTRACE_SIZE = 8 # arbitrary limit to avoid sending back a huge amount of data

      def initialize(tracer)
        @tracer = tracer
        @errors = nil
      end

      def to_h
        {
          "total" => total_h,
          "preparation" => preparation_array,
          "execution" => execution_h,
        }
      end

      def errors
        @errors ||= begin
          errs = []
          if @tracer.field_profile_path && !@tracer.field_was_profiled?
            errs << {
              "message" => "Didn't profile #{@tracer.field_profile_type.inspect} for #{@tracer.field_profile_path.inspect}, matching path was not found.",
              "extensions" => {
                "path" => @tracer.field_profile_path,
                "type" => @tracer.field_profile_type.inspect,
              },
            }
          end
          errs
        end
      end

      private

      def total_h
        {
          "duration_ms" => @tracer.duration * 1000,
          "allocated_objects_count" => @tracer.gc_objects,
        }
      end

      # @return [Array<Hash>] Phases before execution, in the order they occur
      def preparation_array
        @tracer.phase_timings.map do |pt|
          {
            "name" => pt.name,
            "duration_ms" => pt.duration * 1000,
            "allocated_objects_count" => pt.allocated_objects_count,
          }
        end
      end

      def fallbacks(query)
        prefix = "fallback:"
        query.tags.flatten
          .filter { |tag| tag.start_with?(prefix) }
          .map { |tag| tag.sub(prefix, "") }
          .sort
      end

      def execution_h
        result_timing = { "__trace" => { "children_duration_ms" => 0 } }
        sql_queries = []

        # Let each timing find its place in the timing hash,
        # then populate its data there
        @tracer.step_timings.each do |ft|
          target_timing = result_timing
          parent_traces = []
          ft.path.each do |path_part|
            parent_traces << target_timing["__trace"]
            target_timing = target_timing[path_part] ||= {
              # Use double-underscore for this field's stats.
              # Technically, a field alias could conflict with this,
              # but let's cross that bridge when (if) we get to it.
              # (We could put selections inside `"selections" => {}` to avoid a conflict.)
              #
              # The trace starts out empty and we only add keys if
              # there's actually data for that key.
              "__trace" => { "duration_ms" => 0 },
            }
          end

          target_trace = target_timing["__trace"]
          target_trace["duration_ms"] += ft.duration * 1000
          target_trace["catalog_service"] = ft.catalog_service

          # Add this field's timing to the traces above it.
          parent_traces.each do |t|
            t["children_duration_ms"] ||= 0
            t["children_duration_ms"] += ft.duration * 1000
          end

          if ft.mysql_calls.any?
            mysql = target_trace["mysql"] ||= { "count" => 0, "duration_ms" => 0, "calls" => [] }
            ft.mysql_calls.each do |c|
              mysql["duration_ms"] += (c.duration ? c.duration * 1000 : 0)
              mysql["count"] += 1
              mysql["calls"] << {
                "duration_ms" => c.duration ? c.duration * 1000 : "CACHE",
                "result_count" => c.result_count,
                "sql" => c.sql.gsub(%r{/\*ap.+\*/\z}, "").force_encoding("utf-8").squish.scrub!,
                "digested_sql" => c.digested_sql.gsub(%r{/\*ap.+\*/\z}, "").force_encoding("utf-8").squish.scrub!,
                "backtrace" => c.backtrace.first&.to_s,
                "cluster_name" => c.connection_class.name,
                "fallbacks" => fallbacks(c),
                # Could also include connection, but it's very noisy!
              }

              sql_queries << {
                "digested_sql" => c.digested_sql,
                "backtrace" => c.backtrace,
                "duration_ms" => c.duration ? c.duration * 1000 : "CACHE",
                "catalog_service" => ft.catalog_service,
              }
            end
          end

          if ft.elastomer_calls.any?
            # We could probably give more details about this,
            # but it's rarely an issue, at least so far.
            elastomer = target_trace["elastomer"] ||= { "count" => 0, "duration_ms" => 0, "calls" => [] }
            elastomer["count"] += ft.elastomer_calls.size
            elastomer["duration_ms"] += ft.elastomer_calls.sum(&:time)
            ft.elastomer_calls.each do |e_call|
              elastomer["calls"] << {
                "duration_ms" => e_call.time,
                "url" => e_call.url.to_s,
                "body" => e_call.original_body,
                "count" => e_call.total
              }
            end
          end

          if ft.memcached_calls_count > 0
            memcached = target_trace["memcached"] ||= { "count" => 0, "duration_ms" => 0 }
            memcached["count"] += ft.memcached_calls_count
            memcached["duration_ms"] += ft.memcached_calls_time * 1000
          end

          if ft.gitrpc_calls.any?
            gitrpc = target_trace["gitrpc"] ||= { "count" => 0, "duration_ms" => 0, "calls" => [] }
            ft.gitrpc_calls.each do |c|
              gitrpc["count"] += 1
              gitrpc["duration_ms"] += c.duration
              gitrpc["calls"] << {
                "command" => "#{c.command}#{c.arguments.any? ? "(#{c.pretty_printed_arguments.strip})" : ""}",
                "duration_ms" => c.duration,
              }
            end
          end

          if ft.allocated_objects.any?
            profile_objects = target_trace["allocated_objects"] ||= Hash.new { |h, k| h[k] = { "count" => 0, "lines" => Hash.new(0) } }
            skip_prefix_length = Rails.root.to_s.length

            ft.allocated_objects.each do |class_name, counts|
              profile_objects[class_name]["count"] += counts[:count]
              counts[:lines].each do |line, count|
                profile_objects[class_name]["lines"][line[skip_prefix_length..-1]] += count
              end
            end
            # Put the most-allocated objects at the top
            sort_hash_in_place(profile_objects) { |_k, v| -v["count"] }
            # sort lines by most allocations to the least allocations
            profile_objects.each do |_object, prof|
              sort_hash_in_place(prof["lines"]) { |_k, v| -v }
            end
          end

          if ft.lines.any?
            profile_lines ||= target_trace["lineprof"] ||= Hash.new { |h, k| h[k] = { "calls" => 0, "io_ms" => 0, "cpu_ms" => 0 } }
            skip_prefix_length = Rails.root.to_s.length
            ft.lines.each do |filepath, file_lines|
              local_file_path = filepath[skip_prefix_length..-1]
              file_lines.each_with_index do |(wall, cpu, calls, _allocations), idx|
                if calls == 0 || idx == 0
                  next
                end
                line = profile_lines["#{local_file_path}:#{idx}"]
                line["calls"] += calls
                line["io_ms"] += (wall - cpu) / 1000.0
                line["cpu_ms"] += cpu / 1000.0
              end
            end
            sort_hash_in_place(profile_lines) { |_h, v| -(v["io_ms"] + v["cpu_ms"]) }
          end
        end

        n_plus1_queries = begin
          grouped_queries = sql_queries.group_by do |q|
            [q["backtrace"].join(""), q["digested_sql"]]
          end.values.select { |values| values.size > 1 }
        end

        result_timing["n_plus1_sql_queries"] = []
        n_plus1_queries.each do |q|
          result_timing["n_plus1_sql_queries"] << {
            "sql" => q.first["digested_sql"],
            "count" => q.size,
            "duration_ms" => q.sum { |x| x["duration_ms"] },
            "backtrace" => q.first["backtrace"].take(MAX_BACKTRACE_SIZE).map(&:to_s),
            "catalog_services" => q.map { |x| x["catalog_service"] }.group_by { |cs| cs }.map { |cs, a| [cs, a.count] }.to_h
          }
        end
        result_timing["n_plus1_sql_queries"].sort_by! { |x| -x["duration_ms"] }

        result_timing
      end

      # Apparently Hash#sort_by! isn't a thing, so use this to
      # sort detailed profile results into largest-first order.
      def sort_hash_in_place(hash)
        ordered_values = hash.to_a.sort_by { |(k, v)| yield(k, v) }
        hash.clear
        ordered_values.each { |k, v| hash[k] = v }
        nil
      end
    end
  end
end
