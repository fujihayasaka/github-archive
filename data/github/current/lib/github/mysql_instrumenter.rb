# typed: false
# frozen_string_literal: true

require "database_selector"
require "github/sql/digester"
require "github/datadog_tags_cache"

module GitHub
  module MysqlInstrumenter
    RAILS_ROOT_PATH = "#{GitHub::AppEnvironment.root.realpath}/".freeze
    RAILS_ROOT_REGEXP = /^#{Regexp.escape RAILS_ROOT_PATH}(app|lib|packages\/.+\/app)/

    # Private: The regex to match select queries.
    COMMENT_REGEXP = /\/\*(?:[^*]|\*[^\/])*\*\//mi.freeze
    OPT_COMMENT_REGEXP = /(?:(?:#{COMMENT_REGEXP}[\s]*)|(?:\A[\s]*))/mi.freeze

    # Private: The regex to match an optional leading comment segment.
    SELECT_REGEXP = /#{OPT_COMMENT_REGEXP}select.*?from\s*`?([\w$]+)`?\.?`?([\w$]+)?`?/mi.freeze

    # Private: These all need to be liberal about allowing keywords like
    # LOW_PRIORITY, IGNORE, QUICK, etc. in between the verb and the
    # other keywords.
    INSERT_REGEXP = /#{OPT_COMMENT_REGEXP}insert(?:\W+\w+)*?\W+into\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze
    UPDATE_REGEXP = /#{OPT_COMMENT_REGEXP}update(?:\W+\w+)*?\W+([\w$]+)\W+set/mi.freeze
    DELETE_REGEXP = /#{OPT_COMMENT_REGEXP}delete(?:\W+\w+)*?\W+from\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze
    REPLACE_REGEXP = /#{OPT_COMMENT_REGEXP}replace(?:\W+\w+)*?\W+into\W+`?([\w$]+)`?\.?`?([\w$]+)?/mi.freeze

    @subscription_count = 0

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
               :queries_per_table, :queries_per_table=,
               :cluster_names, :cluster_names=,
               :rows_per_type_database, :rows_per_type_database=,
               :queries_per_type_database, :queries_per_type_database=,
               :query_times_per_database, :query_times_per_database=,
               :active_record_obj_count, :active_record_obj_count=,
               :active_record_obj_types, :active_record_obj_types=,
               :undegradable_queries_per_cluster, :undegradable_queries_per_cluster=,
               :query_stats, :query_stats=,
               :cluster_hosts, :cluster_hosts=,
               :cached_queries, :cached_queries=,
               :cached_query_count, :cached_query_count=,
               :within_graceful_degradation_wrapper, :within_graceful_degradation_wrapper=,
               to: :collector
    end

    def self.collector
      GitHub::DataCollector::MysqlInstrumenterCollector.get_instance
    end

    def self.track_degradable_queries
      old_state = self.within_graceful_degradation_wrapper
      self.within_graceful_degradation_wrapper = true
      yield
    ensure
      self.within_graceful_degradation_wrapper = old_state
    end

    def self.tag_queries(*tags)
      self.tags.concat(tags)
      yield
    ensure
      self.tags.pop(tags.size)
    end

    def self.report_stats(controller, action, method, catalog_service, controller_instance, rest_api_read_from_replicas = false, tags_cache = nil)
      controller_tag = tags_cache&.[](GitHub::TaggingHelper::CONTROLLER_TAG) || "#{GitHub::TaggingHelper::CONTROLLER_TAG}:#{controller}"
      method_tag = tags_cache&.[](GitHub::TaggingHelper::METHOD_TAG) || "#{GitHub::TaggingHelper::METHOD_TAG}:#{method}"
      action_tag = tags_cache&.[](GitHub::TaggingHelper::ACTION_TAG) || "#{GitHub::TaggingHelper::ACTION_TAG}:#{action}"
      catalog_service_tag = tags_cache&.[](GitHub::TaggingHelper::CATALOG_SERVICE_TAG) || "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:#{catalog_service}"
      cluster_status_tags = self.cluster_statuses(controller_instance) || {}
      rest_api_read_from_replicas_tag = "#{GitHub::TaggingHelper::REST_API_READ_FROM_REPLICAS_TAG}:#{rest_api_read_from_replicas}"

      self.query_stats.each do |cluster_name, cluster_stats|
        cluster_tag = GitHub::DatadogTagsCache::SQL_CLUSTER_NAMES[cluster_name] || "cluster:#{cluster_name}"

        cluster_stats.each do |connection_role, connection_role_stats|
          connection_role_tag = GitHub::DatadogTagsCache::SQL_CONNECTION_ROLES[connection_role]
          db_host_tag = "rpc_host:#{self.cluster_hosts[cluster_name][connection_role]}"
          tags = [action_tag, controller_tag, method_tag, catalog_service_tag, cluster_tag, connection_role_tag, db_host_tag, rest_api_read_from_replicas_tag]
          tags << cluster_status_tags[cluster_name] if cluster_status_tags[cluster_name]

          reads, writes = connection_role_stats[:read], connection_role_stats[:write]
          GitHub.dogstats.distribution("request.rpc.mysql.dist.queries", reads, tags: tags + ["operation_type:read"]) if reads > 0
          GitHub.dogstats.distribution("request.rpc.mysql.dist.queries", writes, tags: tags + ["operation_type:write"]) if writes > 0
        end
      end

      self.rows_per_type_database.each do |db_host, rows|
        tags_with_host = [action_tag, controller_tag, method_tag, "rpc_host:#{db_host}"]
        GitHub.dogstats.distribution("request.rpc.mysql.count.rows", rows, tags: tags_with_host) if rows > 0
      end

      self.undegradable_queries_per_cluster.each do |cluster_name, queries|
        cluster_tag = GitHub::DatadogTagsCache::SQL_CLUSTER_NAMES[cluster_name] || "cluster:#{cluster_name}"
        tags = [action_tag, controller_tag, method_tag, catalog_service_tag, cluster_tag]
        cluster_status_tag = cluster_status_tags[cluster_name] || "status:unknown"
        tags << cluster_status_tag

        if queries > 0 && cluster_status_tag != "status:required"
          GitHub.dogstats.distribution("request.rpc.mysql.dist.undegradable_queries", queries, tags: tags)
        end
      end
    end

    def self.cluster_statuses(controller_instance)
      return unless !controller_instance.nil? && controller_instance.respond_to?(:required_clusters)

      required_clusters = Array(controller_instance.required_clusters).map(&:name)
      optional_clusters = Array(controller_instance.optional_clusters).map(&:name)

      self.queries_per_database.keys.map do |connection_class|
        status_tag = case connection_class
        when *required_clusters
          "status:required"
        when *optional_clusters
          "status:optional"
        else
          "status:undeclared"
        end

        cluster = self.cluster_names[connection_class] || TaggingHelper::UNKNOWN

        [cluster, status_tag]
      end.to_h
    end

    def self.reset_stats
      collector.reset
    end

    def self.track_cached_query(payload)
      self.cached_query_count += 1
      return unless self.tracking?

      connection = payload.fetch(:connection)
      self.cached_queries << Query.new(
        sql: payload[:sql],
        result_count: payload[:row_count],
        duration: nil,
        connection_url: connection.connection_url,
        on_primary: false,
        connection_class: connection.connection_class,
        skip: self.skip
      )
    end

    def self.track_query(start, finish, payload, result_count: nil, should_record_stats: true)
      time_span = TimeSpan.new(start, finish)

      connection = payload[:connection]
      connection_class = connection&.connection_class
      connection_class = ApplicationRecord::Mysql1 if defined?(ActiveRecord::Base) && connection_class == ActiveRecord::Base
      connection_info = ConnectionInfo.new(
        url: connection.connection_url,
        connection_class: connection_class,
        connection_role: connection_class&.current_role
      )

      sql = payload[:sql]
      type = connection.respond_to?(:write_query?) && connection.write_query?(sql) ? :write : :read

      ::DatabaseSelector::ReplicationState.current&.observe_query!(
        cluster: connection_class,
        type: type
      ) if connection_class

      result_count ||= payload[:row_count]
      on_primary = connection_info.connection_role == :writing
      cluster_name = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name : TaggingHelper::UNKNOWN
      connection_role = connection_info.connection_role || TaggingHelper::UNKNOWN
      connection_class_name = connection_class.respond_to?(:name) ? connection_class.name : connection_class.to_s
      table_name, _ = parse_query(sql)
      undegradable_call = !self.within_graceful_degradation_wrapper

      self.query_time  += time_span.duration_seconds
      self.query_count += 1
      self.primary_query_count += 1 if on_primary
      self.queries_per_type_database[connection_info.config_host][type] += 1
      self.queries_per_database[connection_class_name] += 1
      self.cluster_names[connection_class_name] = cluster_name
      self.query_times_per_database[connection_class_name] += time_span.duration_seconds
      self.rows_per_type_database[connection_class_name] += result_count if result_count
      self.cluster_hosts[cluster_name][connection_role] = connection_info.config_host
      self.queries_per_table[table_name] += 1
      self.undegradable_queries_per_cluster[cluster_name] += 1 if undegradable_call

      if tracking?
        query = Query.new(
          sql: sql,
          result_count: result_count,
          duration: time_span.duration_seconds,
          connection_url: connection_info.url,
          on_primary: on_primary,
          connection_class: connection_class,
          skip: self.skip,
          exception: payload[:exception_object]
        )

        self.queries << query
        self.query_counts[query.digested_sql] += 1
      end

      self.query_stats[cluster_name][connection_role][type] += 1

      return unless should_record_stats

      table, operation = parse_query(sql)
      return unless table && operation

      record_stats(
        operation: operation,
        duration: time_span.duration,
        table: table,
        connection_info: connection_info,
        exception: payload[:exception_object],
        async: payload[:async],
        lock_wait: payload[:lock_wait],
        sql: payload[:sql],
      )

      if payload.has_key?(:exception_object) && payload[:exception_object].instance_of?(ActiveRecord::StatementTimeout)
        CanceledQueryReporter.call(
          query: payload[:sql],
          connection: payload[:connection],
          start: start,
          finish: finish,
        )
      end

      # TODO Make this opt-in for limited time and/or sample count. Queries are already in quoroner.
      # This only adds execution context (backtrace) but is too expensive to collect 100%.
      if SlowQueryReporter.report_slow_query?(time_span.duration_seconds)
        SlowQueryReporter.new(
          sql, time_span.duration_seconds, connection_info
        ).report
      end
    end

    def self.backtrace_locations
      caller_locations(4)
        .select { |f| (f.absolute_path || f.path) =~ RAILS_ROOT_REGEXP }
        .drop_while { |f| !Rollup.significant?(f.absolute_path || f.path) }
        .drop_while { |f| (f.absolute_path || f.path).end_with?("connection_adapter_disabler.rb") }
        .drop_while { |f| (f.absolute_path || f.path).end_with?("connection_adapter_telemetry.rb") }
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

    def self.with_instrument_and_track(skip: [], &block)
      @subscription_count += 1
      Trilogy::QuerySubscriber.subscribe # rubocop:disable GitHub/DoNotReferenceTrilogy
      Trilogy::ActiveRecordInstantiationSubscriber.subscribe # rubocop:disable GitHub/DoNotReferenceTrilogy

      with_track(skip: skip, &block)
    ensure
      @subscription_count -= 1
      if @subscription_count == 0
        Trilogy::QuerySubscriber.unsubscribe # rubocop:disable GitHub/DoNotReferenceTrilogy
        Trilogy::ActiveRecordInstantiationSubscriber.unsubscribe # rubocop:disable GitHub/DoNotReferenceTrilogy
      end
    end

    private_class_method def self.parse_query(sql)
      return if sql.nil?

      table = nil

      operation_key = case sql.b
      when SELECT_REGEXP
        table = $2 ? $2 : $1
        :select
      when UPDATE_REGEXP
        table = $1
        :update
      when INSERT_REGEXP
        table = $2 ? $2 : $1
        :insert
      when DELETE_REGEXP
        table = $2 ? $2 : $1
        :delete
      when REPLACE_REGEXP
        table = $2 ? $2 : $1
        :replace
      else
        return
      end

      # If we got to here, then table will have a non-nil value due to the
      # regexes requiring a table in the query string
      table.downcase! if table

      [table, operation_key]
    end

    private_class_method def self.record_stats(operation:, duration:, connection_info:, table:, exception: nil, async: false, lock_wait: nil, sql: nil)
      connection_class = connection_info.connection_class
      rpc_operation = GitHub::DatadogTagsCache::SQL_OPERATIONS[operation]
      cluster_name = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name : :unknown
      cluster = GitHub::DatadogTagsCache::SQL_CLUSTER_NAMES[cluster_name] || "cluster:#{cluster_name}"
      connection_role = GitHub::DatadogTagsCache::SQL_CONNECTION_ROLES[connection_info.connection_role]
      catalog_service = "catalog_service:#{GitHub.context[:catalog_service] || "unknown"}"
      mysql_table = "mysql_table:#{table}" if table
      db_host = "rpc_host:#{connection_info.config_host}"

      if exception
        exception_error_code = "exception_error_code:#{exception.error_code}" if exception.respond_to?(:error_code)
        exception_class = "exception_class:#{exception.class.name}"
        exception = "exception:true"
      end

      if exception
        tags = [cluster, connection_role, rpc_operation, db_host]
        tags << mysql_table if mysql_table
        tags << exception_class if exception_class
        tags.concat(GitHub.context[:remote_call_source_datadog_tags]) if GitHub.context[:remote_call_source_datadog_tags]
        GitHub.dogstats.increment("rpc.mysql.count.errors", tags: tags)
      end

      tags = [catalog_service, cluster, connection_role, rpc_operation, db_host]
      tags.concat(GitHub.context[:remote_call_source_datadog_tags]) if GitHub.context[:remote_call_source_datadog_tags]
      if mysql_table
        owning_domain = GitHub.packageowners.package_owner_for(table) || "unknown"
        calling_domain = GitHub::DomainIsolation.current_domain || "unknown"
        package = "package:#{owning_domain}"
        uses_domain = owning_domain == calling_domain && owning_domain != "unknown" ? "uses_domain:true" : "uses_domain:false"
        tags << mysql_table
        tags << package
        tags << uses_domain
      end

      GitHub.dogstats.distribution("rpc.mysql.dist.time", duration, tags: tags)

      if async
        catalog_service = "catalog_service:#{catalog_service_from(sql)}"
        tags = [catalog_service, cluster, connection_role, mysql_table]
        GitHub.dogstats.distribution("active_record.load_async.db_time.time", duration, tags: tags)
        GitHub.dogstats.distribution("active_record.load_async.lock_wait.time", lock_wait, tags: tags)
      end
    end

    private_class_method def self.catalog_service_from(sql)
      sql.match(/.*catalog_service:(?<catalog_service>[A-Za-z_\/]+)/)[:catalog_service]
    end
  end

  class TimeSpan
    attr_reader :starting, :ending

    def initialize(starting, ending)
      @starting = starting
      @ending = ending
    end

    def duration_seconds
      @duration_seconds ||= @ending - @starting
    end

    def duration
      @duration = duration_seconds * 1_000
    end

    def ==(other)
      starting == other.starting && ending == other.ending
    end
  end
end
