# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class MysqlInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.start = Time.now
        collector.query_count = 0
        collector.primary_query_count = 0
        collector.query_time = 0
        collector.queries = []
        collector.query_counts = Hash.new(0)
        collector.cached_query_count = 0
        collector.cached_queries = []
        collector.tracking = false
        collector.skip = nil
        collector.tags = []
        collector.queries_per_database = Hash.new(0)
        collector.queries_per_table = Hash.new(0)
        collector.cluster_names = {}
        collector.queries_per_type_database = Hash.new { |h, k| h[k] = Hash.new(0) }
        collector.query_times_per_database = Hash.new(0)
        collector.active_record_obj_count = 0
        collector.active_record_obj_types = Hash.new(0)
        collector.rows_per_type_database = Hash.new(0)
        collector.undegradable_queries_per_cluster = Hash.new(0)
        collector.cluster_hosts = Hash.new do |clusters, cluster|
          clusters[cluster] = Hash.new do |connection_roles, connection_role|
            connection_roles[connection_role] = "unknown"
          end
        end
        collector.query_stats = Hash.new do |clusters, cluster|
          clusters[cluster] = Hash.new do |connection_roles, connection_role|
            connection_roles[connection_role] = Hash.new do |operation_types, operation_type|
              operation_types[operation_type] = 0
            end
          end
        end
        collector.within_graceful_degradation_wrapper = false
      end

      attributes :start,
        :query_count,
        :primary_query_count,
        :query_time,
        :queries,
        :query_counts,
        :tracking,
        :skip,
        :tags,
        :queries_per_database,
        :queries_per_table,
        :cluster_names,
        :queries_per_type_database,
        :query_times_per_database,
        :active_record_obj_count,
        :active_record_obj_types,
        :rows_per_type_database,
        :query_stats,
        :cluster_hosts,
        :cached_query_count,
        :cached_queries,
        :undegradable_queries_per_cluster,
        :within_graceful_degradation_wrapper,

      def self.collector_name
        :mysql_instrumenter_collector
      end
    end
  end
end
