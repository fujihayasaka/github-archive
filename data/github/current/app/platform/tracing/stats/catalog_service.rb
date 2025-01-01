# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module Stats
      class CatalogService
        attr_reader :name, :fields

        def initialize(name, steps, track_n_plus_one, tags = [])
          @name = name
          @fields = steps.group_by(&:gql_path)
          @track_n_plus_one = track_n_plus_one
          @report_field_stats = GitHub.flipper[:gql_report_field_stats].enabled?
          @tags = tags + ["catalog_service:#{name}"]
        end

        def report
          stats.each do |stat, value|
            next if value.zero?
            GitHub.dogstats.distribution("platform.query.dist.#{stat}.by_catalog_service", value, tags: @tags)
          end
        end

        def report_field_stats(stats)
          return unless @report_field_stats

          stats.each do |name, steps|
            GitHub.dogstats.distribution("platform.query.dist.field.time", steps.sum(&:duration) * 1000, tags: @tags + ["gql_path:#{name}"])
          end
        end

        # Right now we are aggregating all the steps for a given catalog service.
        # we can change this in the future to aggregate by field.
        def stats
          stats = {
            "field.time": 0,
            "field.count": 0,
            "field.mysql.count": 0,
            "field.mysql.time": 0,
            "field.mysql.primary.count": 0,
            "field.mysql.n_plus_one.count": 0,
            "field.gitrpc.count": 0,
            "field.gitrpc.time": 0,
            "field.memcached.count": 0,
            "field.memcached.time": 0,
            "field.elastomer.count": 0,
            "field.elastomer.time": 0,
            "field.redis.count": 0,
            "field.redis.time": 0,
            "field.allocated_objects.count": 0,
            "field.active_record.cached_count": 0,
          }

          @fields.each do |_, steps|
            steps.each do |step|
              stats[:"field.time"] += step.duration * 1000 # convert to ms
              stats[:"field.mysql.count"] += step.mysql_count
              stats[:"field.mysql.time"] += step.mysql_time
              stats[:"field.mysql.n_plus_one.count"] += step.n_plus1_queries.size if @track_n_plus_one
              stats[:"field.mysql.primary.count"] += step.primary_queries.size
              stats[:"field.gitrpc.count"] += step.gitrpc_calls.size
              stats[:"field.gitrpc.time"] += step.gitrpc_calls.sum(&:duration) # already in ms
              stats[:"field.memcached.count"] += step.memcached_calls_count
              stats[:"field.memcached.time"] += step.memcached_calls_time * 1000 # convert to ms
              stats[:"field.elastomer.count"] += step.elastomer_calls.size
              stats[:"field.elastomer.time"] += step.elastomer_calls.sum(&:time) # already in ms
              stats[:"field.redis.count"] += step.redis_calls.size
              stats[:"field.redis.time"] += step.redis_calls.sum(&:duration) # already in ms
              stats[:"field.allocated_objects.count"] += step.allocated_objects_count
              stats[:"field.active_record.cached_count"] += step.mysql_cache_hits.size
            end

            # we merge lazy calls with their non-lazy counterparts
            grouped_stats = steps.group_by(&:name)
            stats[:"field.count"] += steps.group_by(&:name).size

            report_field_stats(grouped_stats)
          end

          stats
        end
      end
    end
  end
end
