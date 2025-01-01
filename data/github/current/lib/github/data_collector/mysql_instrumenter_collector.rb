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
        collector.tracking = false
        collector.skip = nil
        collector.tags = []
        collector.queries_per_database = Hash.new(0)
        collector.cluster_names = {}
        collector.queries_per_type_database = Hash.new { |h, k| h[k] = Hash.new(0) }
        collector.query_times_per_database = Hash.new(0)
        collector.active_record_obj_count = 0
        collector.active_record_obj_types = Hash.new(0)
        collector.rows_per_type_database = Hash.new(0)
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
        :cluster_names,
        :queries_per_type_database,
        :query_times_per_database,
        :active_record_obj_count,
        :active_record_obj_types,
        :rows_per_type_database

      def self.collector_name
        :mysql_instrumenter_collector
      end
    end
  end
end
