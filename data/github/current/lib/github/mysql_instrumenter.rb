# typed: false
# frozen_string_literal: true

require "github/sql/subscriber"
require "github/sql/digester"

module GitHub
  module MysqlInstrumenter
    RAILS_ROOT_PATH = "#{GitHub::AppEnvironment.root.realpath}/".freeze
    RAILS_ROOT_REGEXP = /^#{Regexp.escape RAILS_ROOT_PATH}(app|lib|packages\/.+\/app)/

    extend GitHub::SQL::Digester

    class Query
      attr_reader :sql, :digested_sql, :start_time, :duration, :backtrace, :result_count, :connection_url, :tags, :on_primary, :connection_class, :exception

      def initialize(sql:, result_count:, duration:, connection_url:, on_primary:, connection_class:, skip: [], exception: nil)
        @sql = sql
        @result_count = result_count
        @start_time = Time.now - MysqlInstrumenter.start
        @duration = duration
        @connection_url = connection_url
        @connection_class = connection_class
        @on_primary = on_primary
        @skip = skip
        @exception = exception

        @backtrace = skip?(:backtrace) ? [] : MysqlInstrumenter.backtrace_locations
        @digested_sql = skip?(:digested_sql) ? sql : GitHub::SQL::Digester.digest_sql(sql)
        @tags = skip?(:tags) ? [] : MysqlInstrumenter.tags.uniq

        freeze
      end

      def skip?(attribute)
        @skip&.include?(attribute)
      end
    end

    class << self
      delegate :start, :query_count, :query_count=,
               :primary_query_count, :primary_query_count=,
               :query_time, :query_time=,
               :queries, :queries=,
               :query_counts, :query_counts=,
               :tracking, :tracking=,
               :skip, :skip=,
               :tags, :tags=,
               :queries_per_database, :queries_per_database=,
               :cluster_names, :cluster_names=,
               :rows_per_type_database, :rows_per_type_database=,
               :queries_per_type_database, :queries_per_type_database=,
               :query_times_per_database, :query_times_per_database=,
               :active_record_obj_count, :active_record_obj_count=,
               :active_record_obj_types, :active_record_obj_types=,
               to: :collector
    end

    def self.collector
      GitHub::DataCollector::MysqlInstrumenterCollector.get_instance
    end

    def self.tag_queries(*tags)
      self.tags.concat(tags)
      yield
    ensure
      self.tags.pop(tags.size)
    end

    def self.report_stats(controller, action, method, catalog_service)
      controller = "#{GitHub::TaggingHelper::CONTROLLER_TAG}:#{controller}"
      method = "#{GitHub::TaggingHelper::METHOD_TAG}:#{method}"
      action = "#{GitHub::TaggingHelper::ACTION_TAG}:#{action}"

      GitHub::MysqlInstrumenter.queries_per_type_database.each do |db_host, counts|
        reads, writes = counts[:read].to_i, counts[:write].to_i
        tags_with_host = [controller, action, method, "rpc_host:#{db_host}"]

        GitHub.dogstats.distribution("request.rpc.mysql.count.reads", reads, tags: tags_with_host) if reads > 0
        GitHub.dogstats.distribution("request.rpc.mysql.count.writes", writes, tags: tags_with_host) if writes > 0
      end

      GitHub::MysqlInstrumenter.rows_per_type_database.each do |db_host, rows|
        tags_with_host = [action, controller, "rpc_host:#{db_host}"]
        GitHub.dogstats.distribution("request.rpc.mysql.count.rows", rows, tags: tags_with_host) if rows > 0
      end
    end

    def self.reset_stats
      collector.reset
    end

    def self.track_query(sql, type, connection_info, time_span:, result_count: 0, should_record_stats: true, exception: nil, async: false, lock_wait: nil)
      connection_class = connection_info.connection_class
      on_primary = connection_info.connection_role == :writing
      diff = time_span.duration_seconds
      cluster_name = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name : "unknown"
      self.query_time  += diff
      self.query_count += 1
      self.primary_query_count += 1 if on_primary
      self.queries_per_type_database[connection_info.config_host.to_s][type] += 1
      self.queries_per_database[connection_class.to_s] += 1
      self.cluster_names[connection_class.to_s] = cluster_name
      self.query_times_per_database[connection_class.to_s] += diff
      self.rows_per_type_database[connection_class.to_s] += result_count if result_count

      if tracking?
        query = Query.new(
          sql: sql,
          result_count: result_count,
          duration: diff,
          connection_url: connection_info.url,
          on_primary: on_primary,
          connection_class: connection_class,
          skip: self.skip,
          exception: exception
        )

        self.queries << query
        self.query_counts[query.digested_sql] += 1
      end

      GitHub::SQL::Subscriber.call(sql, connection_info, time_span: time_span, exception: exception, async:, lock_wait:) if should_record_stats
    end

    def self.backtrace_locations
      caller_locations(4)
        .select { |f| (f.absolute_path || f.path) =~ RAILS_ROOT_REGEXP }
        .drop_while { |f| !Rollup.significant?(f.absolute_path || f.path) }
        .drop_while { |f| (f.absolute_path || f.path).end_with?("connection_adapter_disabler.rb") }
        .drop_while { |f| (f.absolute_path || f.path).end_with?("database_query_disabler.rb") }
    end

    def self.track!
      self.collector.enable
      self.collector.tracking = true
    end

    def self.untrack!
      self.collector.tracking = false
      self.collector.disable
    end

    def self.tracking?
      self.tracking
    end

    def self.skip!(skip, old_skip)
      # nil means it wasn't previously set
      return self.skip = skip if old_skip.nil?

      # We need to intersect the skip option to ensure we don't miss
      # any required attributes from a higher `with_track` call.
      self.skip = skip.intersection(old_skip)
    end

    # This method is used to temporarily enable MySQL tracking for a block of code.
    # @params skip [Array<Symbol>] An array of attributes to skip tracking for.
    #                      Valid options are: :backtrace, :digested_sql, :tags
    def self.with_track(skip: [], &block)
      old_skip = self.skip
      old_tracking = tracking?
      begin
        track!
        self.skip!(skip, old_skip)

        block.call
      ensure
        self.skip = old_skip
        old_tracking ? track! : untrack!
      end
    end
  end
end
