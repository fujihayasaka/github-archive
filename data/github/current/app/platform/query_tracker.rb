# typed: true
# frozen_string_literal: true

require "elastomer/query_stats"

module Platform
  class QueryTracker
    # Internal: Wraps the execution of a query to provide tracking of some
    # basic performance data, including SQL queries, field resolution timings,
    # and the number of loaded ActiveRecord associations.
    #
    # document  - The GraphQL::Language::Nodes::Document from the parsed query.
    # context   - The Hash used for query execution
    # variables - A Hash of variables used for query execution
    #
    # Returns a hash poplated with the performance data, intended to be merged
    # into the response for site admins.

    attr_reader :document, :context, :variables,
      :query_string, :dog_tags, :dog_sql_tags,
      :origin, :query_depth, :query_complexity, :mysql_counts,
      :performance_data_total_sql, :mysql_count, :gitrpc_count, :gitrpc_time_ms, :rate_limited, :clock_times, :elastomer_query_count, :elastomer_query_time_ms,
      :query, :query_name, :query_hash, :variables_hash, :query_byte_size, :variables_byte_size,
      :real_start, :cpu_start, :gitrpc_before_count,
      :gitrpc_before_time, :catalog_service, :operation_id, :authzd_batch_authorize_count,
      :authzd_batch_authorize_time_ms, :execution_type, :defer_label, :streamed_chunks_count

    # Returns an Array of GraphQL::Schema::Objects which were accessed during the query
    attr_reader :accessed_objects

    # Returns a set of type names that were fetched through a global ID / node interface
    attr_reader :fetched_node_id_types

    # Returns an Array of Platform::QueryTracker containing trackers for each deferred fragment
    attr_reader :deferred_fragment_trackers

    attr_accessor :rate_limit_request_query, :query_cost, :response

    sig { returns(Platform::Analyzers::QueryCoster::PotentialQueryCosts) }
    attr_accessor :potential_query_costs

    attr_accessor :length_of_largest_alias

    sig { params(query: GraphQL::Query, query_hash: T.nilable(String), request_env: T.untyped, execution_type: T.nilable(String), defer_label: T.nilable(String)).void }
    def initialize(query, query_hash: nil, request_env: nil, execution_type: "main", defer_label: nil)
      @query                          = query
      @document                       = query.document
      @context                        = query.context
      @variables                      = query.provided_variables
      @query_string                   = @context[:query_string] || @document.to_query_string
      @query_byte_size                = @query_string.bytesize
      @variables_byte_size            = @variables.to_s.bytesize
      @origin                         = @context[:origin]
      @query_hash                     = query_hash || Platform::Instrumentation::TrackingHash.generate(@query.context[:query_string] || "")
      @variables_hash                 = Platform::Instrumentation::TrackingHash.generate(@variables.to_json)
      @query_name                     = @context[:query_name]
      @catalog_service                = @context[:catalog_service]
      @performance_data_total_sql     = 0
      @mysql_count                    = 0
      @gitrpc_count                   = 0
      @gitrpc_time_ms                 = 0
      @allocated_objects_count        = 0
      @elastomer_query_count          = 0
      @elastomer_query_time_ms        = 0
      @authzd_batch_authorize_count   = 0
      @authzd_batch_authorize_time_ms = 0
      @tracked_associations           = {}
      @query_depth                    = 0
      @query_cost                     = 0
      @potential_query_costs          = Platform::Analyzers::QueryCoster::PotentialQueryCosts.new(
                                          custom_list_complexity: nil,
                                          custom_list_complexity_node_count_exceeding: nil,
                                          corrected_branch_detection: nil,
                                          total_node_count_branch_detection: nil
                                        )
      @defer_label                    = defer_label
      @query_complexity               = 0
      @rate_limit_request_query       = false
      @rate_limited                   = false
      @clock_times                    = { real: 0, cpu: 0, idle: 0 }
      @accessed_objects               = {}
      @fetched_node_id_types          = Set.new
      @operation_id                   = @context[:operation_id]
      @request_env                    = request_env
      @length_of_largest_alias        = 0
      @mysql_counts                   = {
        read: {
          on_primary: 0,
          total: 0,
        },
        write: {
          on_primary: 0,
          total: 0,
        },
      }

      @execution_type = execution_type
      @deferred_fragment_trackers = []
      @streamed_chunks_count = 0
      operation_type = self.class.operation_type_name(query)
      @request_env[GitHub::TaggingHelper::GRAPHQL_OPERATION_TYPE] = operation_type if @request_env
      @dog_tags = T.let([
        GitHub::DatadogTagsCache::ORIGINS[@origin] || "origin:#{@origin}",
        GitHub::DatadogTagsCache::OPERATION_TYPES[operation_type] || "operation_type:#{operation_type}",
        GitHub::DatadogTagsCache::EXECUTION_TYPES[execution_type] || "execution_type:#{@execution_type}",
      ], T::Array[String])

      @dog_tags << "defer_label:#{@defer_label}" if @defer_label.present?

      if @context[:reporting_tags]
        @dog_tags += @context[:reporting_tags]
      end
      @dog_sql_tags = @dog_tags.dup
      if @context[:controller]
        @dog_tags << "controller:#{@context[:controller]}"
      end
      if @query_name.present? && @context[:track_query_name]
        @dog_tags << "gql_operation_name:#{@query_name}"
        @dog_sql_tags << "gql_operation_name:#{@query_name}"
      end
      if @context[:action]
        @dog_tags << "action:#{@context[:action]}"
      end
      if @context[:query_owning_catalog_service]
        @dog_tags << "query_owning_catalog_service:#{@context[:query_owning_catalog_service]}"
      end
      if GitHub.flipper[:add_oauth_app_to_dog_tags].enabled? && @context[:oauth_app]
        @dog_tags << Platform.get_oauth_tags(@context[:oauth_app])
      end
    end

    def track
      track_authzd_calls do
        track_gitrpc_calls do
          track_mysql_queries do
            track_association_loads do
              track_elastomer_queries do
                track_allocated_objects do
                  track_time { yield }
                end
              end
            end
          end
        end
      end

      set_tracked_data
    end

    def rate_limited?
      !!rate_limited
    end

    def rate_limited!
      @rate_limited = true
    end

    def rate_limit_request_query?
      !!rate_limit_request_query
    end

    sig { params(tracker: Platform::QueryTracker).void }
    def add_deferred_fragment_tracker(tracker)
      @deferred_fragment_trackers << tracker
    end

    sig { params(count: Integer).void }
    def set_streamed_chunks_count(count)
      @streamed_chunks_count = count
    end

    # Returns a hash of timing data for this tracker that can be used for logging
    def timing_data
      {
        "name" => @query_name,
        "mysql_time_ms" => @performance_data_total_sql,
        "mysql_count" => @mysql_count,
        "gitrpc_time_ms" => @gitrpc_time_ms,
        "gitrpc_count" => @gitrpc_count,
        "elastomer_query_time_ms" => @elastomer_query_time_ms,
        "elastomer_query_count" => @elastomer_query_count,
        "authzd_batch_authorize_time_ms" => @authzd_batch_authorize_time_ms,
        "authzd_batch_authorize_count" => @authzd_batch_authorize_count,
        "clock_times" => @clock_times.stringify_keys
      }
    end

    # Call the given block, raising an error if an association is loaded without batch loading
    def self.tracking_association_loads(query: nil, path: nil, tracked_associations: nil, &block)
      callback = ->(association) do
        reflection = association.reflection
        current_path = path || query.context.namespace(:interpreter)[:current_field]&.path

        if Rails.env.test?
          raise Errors::AssociationRefused.new(reflection.name, reflection.active_record.name, current_path)
        else
          key_name = reflection.active_record.name.to_s

          if tracked_associations.present?
            tracked_associations[key_name] ||= { count: 0, names: [] }
            tracked_associations[key_name][:count] += 1
            tracked_associations[key_name][:names] << reflection.name
          end

          field_tag = "field:" + current_path&.downcase&.gsub(".", ":")
          GitHub.dogstats.increment("platform.query.associations", tags: ["association:#{key_name.downcase}", field_tag])
        end
      end

      GitHub::AssociationInstrumenter.track_loads(callback, &block)
    end

    sig { params(query: GraphQL::Query).returns(Symbol) }
    def self.operation_type_name(query)
      if query.query?
        :query
      elsif query.mutation?
        :mutation
      elsif query.subscription?
        :subscription
      else
        :unknown
      end
    end

    private

    def set_tracked_data
      @query_depth                       = context[:query_depth]
      @query_complexity                  = context[:query_complexity]
      instrument!
    end

    def instrument!
      data = {
        "gh.request.is_graphql" => true,
        "gh.graphql.time" => @clock_times[:real],
        "gh.graphql.query_byte_size" => @query_byte_size,
        "gh.graphql.variables_byte_size" => @variables_byte_size,
        "graphql.operation.name" => context[:operation_name],
        "gh.graphql.origin" => @origin,
        "gh.graphql.success" => query_success?,
        "gh.graphql.query_depth" => @query_depth,
        "gh.graphql.query_complexity" => @query_complexity,
        "gh.request_id" => GitHub.context[:request_id],
        "gh.graphql.schema" => context[:target],
        "gh.graphql.query_hash" => query_hash,
        "gh.graphql.variables_hash" => variables_hash,
        "gh.graphql.query_name" => @query_name,
        "gh.graphql.operation_id" => @operation_id,
        "gh.graphql.viewer_login" => context[:viewer]&.display_login,
        "gh.graphql.oauth_app_id" => context[:oauth_app]&.id,
        "gh.graphql.integration_id" => context[:integration]&.id,
        "enduser.scope" => context[:granted_oauth_scopes],
        "gh.graphql.additional_data" => context[:log_data] || {},
        "gh.graphql.n_plus_one_tracer_enabled" => GitHub.flipper[:gql_n_plus_one_tracer].enabled?(@context[:viewer]),
        "gh.graphql.execution_type" => @execution_type,
        "gh.graphql.defer_label" => @defer_label,
      }

      if @context[:reporting_tags]
        @context[:reporting_tags].each do |tag|
          matcher = tag.match(/\A([^:]+):(.*)\z/)
          if matcher
            key, value = matcher.captures
            data["gh.tag.#{key}"] = value
          end
        end
      end

      unless @catalog_service.nil?
        data[:catalog_service] = @catalog_service
      end

      if @context[:query_owning_catalog_service]
        data[:query_owning_catalog_service] = @context[:query_owning_catalog_service]
      end

      GitHub.logger.info(data) if GitHub.platform_graphql_logging_enabled?

      distribution_tags = dog_tags + success_tags
      GitHub.dogstats.distribution("platform.query.dist.time", @clock_times[:real], tags: distribution_tags)

      # Since a GraphQL query can touch multiple services, store each touched service in a set.
      # When the request is finished, emit one metric per touched catalog service.
      query.context[:catalog_services]&.each do |catalog_service|
        GitHub.dogstats.distribution(
          "platform.query.dist.time.by_catalog_service",
          @clock_times[:real],
          tags: distribution_tags + ["catalog_service:#{catalog_service}"]
        )
      end

      GitHub.dogstats.distribution("platform.query.dist.allocations", @allocated_objects_count, tags: distribution_tags) if @allocated_objects_count > 0

      mysql_dog_tags = dog_tags + mutation_tags
      @mysql_counts.each do |type, counts|
        case type
        when "read"
          total_metric_name = "platform.query.sql_count.read.total"
          on_primary_metric_name = "platform.query.sql_count.read.on_primary"
        when "write"
          total_metric_name = "platform.query.sql_count.write.total"
          on_primary_metric_name = "platform.query.sql_count.write.on_primary"
        else
          total_metric_name = "platform.query.sql_count.#{type}.total"
          on_primary_metric_name = "platform.query.sql_count.#{type}.on_primary"
        end

        GitHub.dogstats.distribution(total_metric_name, counts[:total], tags: mysql_dog_tags)
        GitHub.dogstats.distribution(on_primary_metric_name, counts[:on_primary], tags: mysql_dog_tags)
      end

      GitHub.dogstats.distribution("platform.query.dist.authzd.batch_authorize.count", @authzd_batch_authorize_count, tags: dog_tags)
      GitHub.dogstats.distribution("platform.query.dist.authzd.batch_authorize.time", @authzd_batch_authorize_time_ms, tags: dog_tags)
    end

    def track_gitrpc_calls(&block)
      @gitrpc_before_count = GitRPCLogSubscriber.rpc_count
      @gitrpc_before_time = GitRPCLogSubscriber.rpc_time
      GitRPCLogSubscriber.stats_tags << "graphql"
      GitRPCLogSubscriber.tags << "graphql:true"
      GitRPCLogSubscriber.with_track(&block)
      gitrpc_after_count = GitRPCLogSubscriber.rpc_count
      gitrpc_after_time = GitRPCLogSubscriber.rpc_time

      @gitrpc_count = gitrpc_after_count - @gitrpc_before_count
      @gitrpc_time_ms = (gitrpc_after_time - @gitrpc_before_time) * 1000
    ensure
      GitRPCLogSubscriber.tags.clear
    end

    def track_allocated_objects
      if GitHub.flipper[:graphql_track_allocated_objects].enabled?
        start_allocated_objects_count = GC.stat(:total_allocated_objects)
        yield
        @allocated_objects_count = GC.stat(:total_allocated_objects) - start_allocated_objects_count
      else
        yield
      end
    end

    def track_time
      @real_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @cpu_start  = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      yield
      cpu  = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - @cpu_start
      real = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @real_start

      @clock_times[:real] = (real * 1000)
      @clock_times[:cpu]  = (cpu * 1000)
      @clock_times[:idle] = (real - cpu) * 1000
    end

    def track_elastomer_queries
      if GitHub.flipper[:graphql_track_elastomer_queries].enabled?
        # See lib/elastomer/query_stats.rb
        stats = Elastomer::QueryStats.instance
        start_time = stats.time
        start_count = stats.count
        yield
        @elastomer_query_time_ms = stats.time - start_time
        @elastomer_query_count = stats.count - start_count
      else
        yield
      end
    end

    def track_mysql_queries
      sql_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, started, ended, _id, payload|
        sql = payload.fetch(:sql)
        connection = payload.fetch(:connection)
        read_or_write = connection.write_query?(sql) ? :write : :read

        on_primary = connection.connection_class.current_role == :writing
        on_primary_tag = on_primary ? GitHub::DatadogTagsCache::ON_PRIMARY_TRUE : GitHub::DatadogTagsCache::ON_PRIMARY_FALSE
        cached_tag = payload[:cached].present? ? GitHub::DatadogTagsCache::CACHED_TRUE : GitHub::DatadogTagsCache::CACHED_FALSE
        type_tag = read_or_write == :read ? GitHub::DatadogTagsCache::TYPE_READ : GitHub::DatadogTagsCache::TYPE_WRITE
        mutations_on_read_tag = @query.context[:read_arguments_from_replicas].present? ? GitHub::DatadogTagsCache::MUTATIONS_ON_READ_TRUE : GitHub::DatadogTagsCache::MUTATIONS_ON_READ_FALSE

        db_tags = [
          on_primary_tag,
          cached_tag,
          type_tag,
          mutations_on_read_tag,
        ]

        duration = (ended - started) * 1_000
        @performance_data_total_sql += duration

        # We only want to count non-cached queries
        unless payload[:cached]
          @mysql_counts[read_or_write][:total] += 1
          @mysql_counts[read_or_write][:on_primary] += 1 if on_primary
          @mysql_count += 1
        end
        tags = dog_sql_tags + db_tags

        GitHub.dogstats.distribution("platform.query.dist.sql.time", duration, tags: tags)
        GitHub.dogstats.increment("platform.query.flipper.sql.count", tags: tags) if sql.include?("FROM flipper_gates")
      end

      GitHub::MysqlInstrumenter.tag_queries("graphql:true") do
        yield
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(sql_subscriber)
    end

    def track_authzd_calls
      authzd_subscriber = ActiveSupport::Notifications.subscribe("authzd.client.timing.batch_authorize") do |_event, started, ended, _transaction_id, _payload|
        @authzd_batch_authorize_time_ms += (ended - started) * 1000
        @authzd_batch_authorize_count += 1
      end

      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(authzd_subscriber)
    end

    def track_association_loads(&block)
      self.class.tracking_association_loads(query: @query, tracked_associations: @tracked_associations, &block)
    end

    def query_success?
      @query.context.errors.empty? && !internal_errors? && !internal_error?
    end

    def internal_errors?
      @query.context[:internal_errors] && @query.context[:internal_errors].any?
    end

    def internal_error?
      @query.context[:internal_error].present?
    end

    def mutation_tags
      [
        @query.context[:read_arguments_from_replicas].present? ? GitHub::DatadogTagsCache::MUTATIONS_ON_READ_TRUE : GitHub::DatadogTagsCache::MUTATIONS_ON_READ_FALSE,
        @query.mutation? ? GitHub::DatadogTagsCache::MUTATION_TRUE : GitHub::DatadogTagsCache::MUTATION_FALSE,
        *("mutation_name:#{@query.context[:mutation_name]}" if @query.mutation?)
      ]
    end

    def success_tags
      [
        internal_error? ? GitHub::DatadogTagsCache::INTERNAL_ERROR_TRUE : GitHub::DatadogTagsCache::INTERNAL_ERROR_FALSE,
        query_success? ? GitHub::DatadogTagsCache::SUCCESS_TRUE : GitHub::DatadogTagsCache::SUCCESS_FALSE,
      ]
    end
  end
end
