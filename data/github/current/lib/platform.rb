# typed: strict
# frozen_string_literal: true

require "graphql"
require "graphql/batch"
require "graphql_monkey_patches"
require "graphql-pro"
require "graphql_pro_monkey_patches"

# remove ActiveRecordBackend from GraphQL::Pro::OperationStore so it cannot be inadvertnetly used
GraphQL::Pro::OperationStore.send(:remove_const, :ActiveRecordBackend)

module Platform
  extend Scientist

  ORIGIN_API = "api"
  ORIGIN_REST_API = "rest_api"
  ORIGIN_INTERNAL = "internal"
  ORIGIN_MANUAL_EXECUTION = "manual_execution"

  # Public: The max number of nodes that can be returned by a query for external
  # uses such as `api` and `rest_api`.
  MAX_NODE_COUNT_EXTERNAL = 500_000

  # Public: The max number of nodes that can be returned by a query for internal
  # uses such as `manual_execution` and `internal`.
  MAX_NODE_COUNT_INTERNAL = 1_020_100

  MAX_BYTE_SIZE = 1_000_000

  MAX_DIRECTIVE_COUNT = 100

  # In the current implementation, list fields are always estimated to have cost of 1.
  # This leads to underestimation of the query's cost when many elements in the list are returned.
  # Temporary solution is to set the default cost of a list to 10, while overriding for some fields if 10 is not the right one.
  # Future correct fix is to switch from lists to connections.
  DEFAULT_LIST_COST = 10

  QUERY_EVENT_KEY = "platform.query"

  FLAGS_TO_PRELOAD = T.let(
    [
      :gql_field_tracer,
      :persisted_tracer_mode,
      :persisted_tracer_debug_mode,
      :gql_n_plus_one_tracer,
      :gql_read_arguments_from_replicas,
      :gql_run_native_analyzers,
      :use_new_graphql_visibility_checks,
      :graphql_track_elastomer_queries,
      :gql_parse_query_with_escape
    ],
    T::Array[Symbol]
  )

  FAILBOT_TAG_KEY_MAPPING = T.let({
    "gh.graphql.url_pattern" => "gh.graphql.referrer.http.route",
    "gh.graphql.referrer_controller_action" => "gh.graphql.referrer.controller_action",
    "gh.graphql.query_owning_catalog_service" => "gh.graphql.catalog_service",
  }, T::Hash[String, String])

  # Public: Primary entry-point for GraphQL query execution.
  #
  # query - The GraphQL query to be executed.
  #
  # context - An arbitrary hash of values which can
  #           be accessed from a resolver.
  #
  # variables - Values for `$variables` in the query.
  #
  # validate - Determines whether or not `query` will be validated
  #            with `GraphQL::StaticValidation::Validator`.
  #
  # raise_exceptions - Determines whether to raise exceptions while
  #                    executing or not.
  #
  # operation_name - The optional operation name. It's only requried if multiple
  #                  operations are present in the query.
  #
  # target - An argument that filters a given schema target from
  #          every query context. Valid values currently include `:public`
  #          and `:internal`.
  #
  # Examples:
  #
  #   Platform.execute(query, target: :internal, context: { viewer: user })
  #
  sig do
    params(
      query: T.any(T.nilable(String), GraphQL::Query, GraphQL::Language::Nodes::Document, Integer),
      target: Symbol,
      schema: T.class_of(GraphQL::Schema),
      context: IContext,
      variables: IRawVariables,
      validate: T::Boolean,
      operation_name: T.nilable(String),
      raise_exceptions: T::Boolean,
      request_env: T.untyped,
      subscription_topic: T.nilable(String),
      enforce_read_only: T::Boolean,
      block_mutations: T::Boolean,
    )
      .returns(Platform::Response)
  end
  def self.execute(
    query,
    target:,
    schema: Platform::Schema,
    context: {},
    variables: {},
    validate: true,
    operation_name: nil,
    raise_exceptions: false,
    request_env: nil,
    subscription_topic: nil,
    enforce_read_only: false,
    block_mutations: false
  )
    ActiveRecord::Base.connected_to(role: :reading) do
      GitHub.tracer.in_span("platform.execute", kind: :internal) do |span|

        prepare_execution_start = GitHub::Dogstats.monotonic_time

        context[:origin] = normalize_origin(context[:origin])
        context[:internal_error] = nil
        context[:raise_exceptions] = raise_exceptions
        context[:session] ||= {}
        context[:target] = target
        context[:warnings] = Platform::Warnings::Collection.new
        context[:mask] = Platform::SchemaRuntimeMask.new(
          context[:target],
          environment: context[:environment] || GitHub.runtime.current
        )

        filtered_flags, platform_preloaded_flags = preload_feature_flags(
          context[:feature_flags],
          user: context[:viewer],
          app: context[:integration] || context[:oauth_app],
        )
        context[:feature_flags] = filtered_flags

        if enforce_read_only
          context[:force_readonly] = enforce_read_only
        end

        # Traffic mirroring
        # We always reject mutations in shadow-lab, otherwise defer to caller
        if block_mutations || GitHub.shadow_lab?
          context[:block_mutations] = true
        end

        context[:trace] = build_tracer(
          schema,
          performance_trace: context[:performance_trace],
          performance_trace_field_profile_path: context[:performance_trace_field_profile_path],
          performance_trace_field_profile_type: context[:performance_trace_field_profile_type],
          viewer: context[:viewer],
          gql_field_tracer: context[:gql_field_tracer],
          is_persisted_query: context[:operation_id].present?
        )

        # Initialize this outside of the `trace do ... end` block
        # so that it can be accessed later, outside the block.
        response = T.let(nil, T.nilable(Platform::Response))

        context[:trace].platform_execute do
          document = T.let(nil, T.nilable(GraphQL::Language::Nodes::Document))
          begin
            query = nil if query.blank?

            # Eagerly load operation from operation ID for persisted queries so we have full query
            # available early for parsing, limiting, analysis, and tracing
            if context[:operation_id]
              query_owning_catalog_service, document = load_query_from_store(
                context[:operation_id],
                schema.operation_store,
                touch_last_used_at: context.fetch(
                  :operation_store_touch_last_used_at,
                  schema.operation_store ? schema.operation_store.default_touch_last_used_at : false
                )
              )
              # this used to compute usage stats for product dashboards
              context[:query_owning_catalog_service] = query_owning_catalog_service
              context[:track_query_name] = true
            end

            if GitHub.flipper[:track_mobile_query_name].enabled? && should_track_query_name_for_oauth_app(context[:oauth_app])
              context[:track_query_name] = true
            end

            context[:query_string] = if query.is_a?(String)
              query.strip
            end

            if document.nil?
              document = parse_query(query, tracer: context[:trace])
            end

            if context[:query_string].nil?
              context[:query_string] = document.to_query_string.strip
            end

            # Set context[:query_name] for observability instrumentation. context[:query_name] may already be set from QueriesController
            context[:query_name] = if context[:track_query_name]
              context[:query_name] || operation_name || document.definitions.first.name
            else
              nil
            end

            # when there is no viewer, only a predefined set of persisted queries are allowed to be executed
            if context[:viewer].nil? && context[:query_name] && context[:anonymous_viewer_query_allowlist].is_a?(Array)
              allowlist = context[:anonymous_viewer_query_allowlist]
              if !allowlist.include?(context[:query_name])
                GitHub.dogstats.increment("platform.query.allowlist_missing", tags: ["query_name:#{context[:query_name]}"])
                raise Platform::Errors::ForbiddenAnonymousQuery.new(context[:operation_id])
              end
            end

            variables = parse_variables(variables)
          rescue Platform::Errors::Parse, GraphQL::ParseError => e
            GitHub.dogstats.increment("platform.query.parse_error")
            span.status = OpenTelemetry::Trace::Status.error
            span.record_exception(e)
            response = Platform::ParseErrorResponse.new(e, provided_context: context, provided_variables: variables)
            response.to_hydro!
            return response
          end

          query_args = {
            document: document,
            context: context,
            variables: variables,
            subscription_topic: subscription_topic,
            validate: validate,
            operation_name: operation_name,
          }

          query = GraphQL::Query.new(
            schema,
            **query_args
          )

          query_hash = Platform::Instrumentation::TrackingHash.generate(context[:query_string] || "")

          preload_cached_feature_flags(viewer: context[:viewer], query_hash: query_hash)

          context[:query_tracker] ||= Platform::QueryTracker.new(query, query_hash: query_hash, request_env: request_env)

          # This adds attributes for better filtering to our distributed tracing.
          # Since tracing is sampled data, adding the query hash will assist
          # in finding performance issues in reoccurring queries.
          tracer_attributes = {
            "gh.graphql.query_hash" => context[:query_tracker].query_hash,
            "gh.graphql.variables_hash" => context[:query_tracker].variables_hash,
          }

          span.add_attributes(tracer_attributes)

          if GitHub.multi_tenant_enterprise?
            context[:tenant_tracker] = Platform::TenantTracker.new(context)
          end

          if request_env && !GitHub.enterprise?
            GitHub::TimeoutMiddleware.notify(request_env, Platform::Response::TimeoutInstrumenter.new(query))
          end

          if request_env
            request_env["github.graphql.operation_name"] = query.selected_operation_name
          end

          context[:scrubbed_query] = scrubbed_query = scrub_query(
            query:,
            origin: context[:origin],
            query_string: context[:query_string],
            skip_scrubbing: context[:operation_id].present?,
          )

          query_details = {
            string: scrubbed_query,
            stats: query.context[:query_tracker].clock_times,
            variables: variables,
            query: query,
          }

          ActiveSupport::ExecutionContext.set(graphql_operation: query.operation_name)
          ActiveSupport::ExecutionContext.set(referrer_controller_action:
            extract_reporting_tags(query).try(:[], :referrer_controller_action))

          Platform::GlobalScope.queries << query_details
          Platform::GlobalScope.mutation = query.mutation?

          # Build the `permission` here so that we can inspect the Query object
          # and determine whether it's a mutation or a query.
          context[:permission] = Platform::Authorization::Permission.new(query.context)

          context[:operation_name] = operation_name
          # In a UI scenario, `actor` will always be set to `viewer`
          # But, in the API, `actor` is set by `current_actor`, which means it *could*
          # be an Integration, or a User. In any event, we enforce the existence of an
          # `actor` here so that it is configured in multiple places (UI, GQL API, and tests)
          context[:actor] ||= context[:viewer]

          # Add some context to Failbot in case an error happens or `Failbot.report`
          failbot_context_keys = {
            "gh.request.is_graphql": true,
            "gh.graphql.schema_target": target,
            "gh.graphql.query_hash": context[:query_tracker].query_hash,
            "gh.graphql.variables_hash": context[:query_tracker].variables_hash,
          }.merge(extract_relevant_context_keys(context))
          Failbot.push(failbot_context_keys)

          tags = T.let([], T::Array[String])
          tags << "query_owning_catalog_service:#{context[:query_owning_catalog_service]}" if context[:query_owning_catalog_service]
          tags += context[:reporting_tags] if context[:reporting_tags]

          prepare_execution_elapsed = GitHub::Dogstats.duration(prepare_execution_start)
          GitHub.dogstats.distribution("platform.query.prepare_execution", prepare_execution_elapsed, tags: tags)

          GitHub.tracer.in_span("platform.query.run", attributes: tracer_attributes, kind: :internal) do |span|
            GitHub.dogstats.distribution_time("platform.query.run", tags: tags) do
              context[:query_tracker].track do
                begin
                  Platform::Security::RepositoryAccess.with_viewer(context[:viewer]) do
                    if GitHub.multi_tenant_enterprise?
                      Platform::TenantTracker.emit_tenant_context_metrics(query, context)
                    end
                    Platform::Session.run(query, context)
                  end
                  instrument_errors!(query)
                rescue => exception # rubocop:todo Lint/GenericRescue
                  # the internal error was not handled by the rescue_form section in the schema.rb and we need to handle it here
                  is_development = Rails.env && Rails.env.development?
                  unless context[:error_reported]
                    query_name = context[:query_name]
                    instrument_internal_errors(query:, query_name:, exception:)
                    # never report internal errors in development unless we are raising them
                    report_internal_errors!(
                      exception:,
                      report_exceptions_to_failbot:  T.must(!is_development && !raise_exceptions),
                      query:,
                      query_name:)
                  end
                  context[:internal_error] = exception
                  span.record_exception(exception)
                  if raise_exceptions || (Rails.env && Rails.env.development?)
                    raise exception
                  end
                ensure
                  cache_preloaded_feature_flags(viewer: context[:viewer], query_hash:, platform_preloaded_flags:)
                  response = Platform::GraphqlResponse.new(query)
                  # This is a bit of a hack to get the response into the query tracker
                  context[:query_tracker].response = response
                  instrument_cap_aggregate_time(cap_aggregate_time: context[:permission].cap_aggregate_time, viewer: context[:viewer])
                end
              end
            end
          end
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          T.must(response).to_hydro!
        end
        response
      end
    end
  end

  sig do
    params(operation_id: String, operation_store: GraphQL::Pro::OperationStore, touch_last_used_at: T::Boolean)
      .returns([String, GraphQL::Language::Nodes::Document])
  end
  def self.load_query_from_store(operation_id, operation_store, touch_last_used_at:)
    catalog_service, digest = extract_client_and_digest(operation_id)
    # client name is required in the GraphQL::Pro gem
    operation_store_result = operation_store.get(
      client_name: catalog_service,
      operation_alias: operation_id,
      touch_last_used_at: touch_last_used_at
    )

    if operation_store_result
      operation_store_result
    else
      GitHub.dogstats.increment("platform.query.operation_store_load_error")
      raise(Platform::Errors::UnknownQuery.new(operation_id))
    end
  end
  private_class_method :load_query_from_store

  sig do
    params(
      requested_feature_flags: T.nilable(T::Array[Symbol]),
      user: T.nilable(User),
      app: T.any(T.nilable(Integration), OauthApplication)
    )
      .returns([T::Array[Symbol], T::Array[Symbol]])
  end
  def self.preload_feature_flags(requested_feature_flags, user: nil, app: nil)
    # Remove any flags which the viewer doesn't actually have
    filtered_flags = Platform::Objects::Base::FeatureFlag.filter_requested_flags(
      requested_feature_flags || [],
      user:,
      app:,
    )
    platform_preloaded_flags = FLAGS_TO_PRELOAD + filtered_flags

    GitHub.flipper.preload(platform_preloaded_flags + [:vexi_preload_platform])
    if GitHub.flipper[:vexi_preload_platform].enabled?
      FeatureFlag.vexi.preload(platform_preloaded_flags)
    end

    [filtered_flags, platform_preloaded_flags]
  end
  private_class_method :preload_feature_flags

  sig { params(viewer: T.nilable(User), query_hash: String).void }
  def self.preload_cached_feature_flags(viewer:, query_hash:)
    cached_flags = Platform::FeatureFlags::Cache.fetch(query_hash)

    if cached_flags.nil?
      GitHub.dogstats.distribution("platform.query.flipper.cache.preloaded_count", 0, tags: ["hit:false"])
    else
      GitHub.dogstats.distribution("platform.query.flipper.cache.preloaded_count", cached_flags.size, tags: ["hit:true"])

      GitHub.flipper.preload(cached_flags + [:vexi_preload_platform])

      if GitHub.flipper[:vexi_preload_platform].enabled?
        FeatureFlag.vexi.preload(cached_flags)
      end
    end
  end
  private_class_method :preload_cached_feature_flags

  sig { params(operation_id: String).returns([String, String]) }
  def self.extract_client_and_digest(operation_id)
    catalog_service, _, digest = operation_id.rpartition(GraphQL::Pro::OperationStore::OPERATION_ID_SEPARATOR)

    catalog_service = Platform::OperationStore::ApplicationRecordBackend::CLIENT_NAME_WILDCARD if catalog_service.blank?

    if digest.blank?
      raise GraphQL::ExecutionError.new("Failed to deconstruct operation id: #{operation_id}, must contain a digest")
    end

    [catalog_service, digest]
  end
  private_class_method :extract_client_and_digest

  sig { params(origin: T.any(T.nilable(String), Symbol)).returns(String) }
  def self.normalize_origin(origin)
    origin = case origin
    when String
      origin
    when nil
      ORIGIN_MANUAL_EXECUTION
    else
      origin.to_s
    end

    Platform::GlobalScope.origin = origin
    origin
  end
  private_class_method :normalize_origin

  sig do
    params(
      query: T.any(String, GraphQL::Language::Nodes::OperationDefinition, GraphQL::Language::Nodes::Document, T.untyped),
      tracer: GraphQL::Tracing::Trace,
    )
      .returns(GraphQL::Language::Nodes::Document)
  end
  def self.parse_query(query, tracer:)

    GitHub.tracer.in_span("platform.parse_query", kind: :internal) do
      case query
      when String
        query_limiter = Platform::Helpers::QueryLimiter.new(query)
        raise Platform::Errors::Parse.new(query_limiter.error_message) if query_limiter.exceeded?

        if GitHub.flipper[:gql_parse_query_with_escape].enabled?
          GraphQL::Parser::Query.parse_with_escape(query, tracer)
        else
          GraphQL.parse(query, trace: tracer)
        end
      when GraphQL::Language::Nodes::OperationDefinition
        GraphQL::Language::Nodes::Document.new(definitions: [query])
      when GraphQL::Language::Nodes::Document # From our own ApplicationController
        query
      else
        raise Platform::Errors::Parse.new("A query attribute must be specified and must be a string.")
      end
    end
  end

  sig do
    params(viewer: T.nilable(User), query_hash: String, platform_preloaded_flags: T::Array[Symbol]).void
  end
  def self.cache_preloaded_feature_flags(viewer:, query_hash:, platform_preloaded_flags:)
    loaded_flags = FlipperSubscriber.tested_features.keys - platform_preloaded_flags
    Platform::FeatureFlags::Cache.write(query_hash, loaded_flags) if loaded_flags.present?
  end
  private_class_method :cache_preloaded_feature_flags

  sig { params(viewer: T.nilable(User), cap_aggregate_time: T.any(T.nilable(Float), Integer)).void }
  def self.instrument_cap_aggregate_time(viewer:, cap_aggregate_time:)
    return unless cap_aggregate_time

    tags = ["anonymous:#{viewer.blank?}"]
    GitHub.dogstats.distribution("cap.internal.api.enforcement.total.dist", cap_aggregate_time, tags: tags)
  end
  private_class_method :instrument_cap_aggregate_time

  sig { params(variables: IRawVariables).returns(IVariables) }
  def self.parse_variables(variables)
    variables = GitHub::JSON.parse(variables) if variables.is_a?(String)

    return variables if variables.is_a?(Hash)

    # GitHub::JSON will parse into things other than hashes (e.g. empty strings
    # into `nil` and "1" into a lone Integer. If we end up with anything but a
    # Hash, just fall back into an empty one.
    Hash.new
  rescue Yajl::ParseError => e
    raise Platform::Errors::Parse.new("Failed to parse variables")
  end
  private_class_method :parse_variables

  sig do
    params(
      schema: T.class_of(GraphQL::Schema),
      performance_trace: T.nilable(T::Boolean),
      performance_trace_field_profile_path: T.nilable(String),
      performance_trace_field_profile_type: T.nilable(Symbol),
      viewer: T.nilable(User),
      gql_field_tracer: T.nilable(T::Boolean),
      is_persisted_query: T.nilable(T::Boolean)
    ).returns(GraphQL::Tracing::Trace)
  end
  def self.build_tracer(
    schema,
    performance_trace: nil,
    performance_trace_field_profile_path: nil,
    performance_trace_field_profile_type: nil,
    viewer: nil,
    gql_field_tracer: nil,
    is_persisted_query: false
  )
    # Add the tracer if it was explicitly requested
    tracer_instance = if performance_trace
      schema.new_trace(
        mode: :performance_trace_mode,
        field_profile_path: performance_trace_field_profile_path,
        field_profile_type: performance_trace_field_profile_type,
      )
    # This is a long term feature flag to allow switching on the persisted tracer debug mode
    elsif GitHub.flipper[:persisted_tracer_debug_mode].enabled?(viewer) && is_persisted_query
      schema.new_trace(
        mode: :persisted_tracer_debug_mode,
      )
    # This is a short term feature flag to test the persisted tracer mode
    elsif GitHub.flipper[:persisted_tracer_mode].enabled?(viewer) && is_persisted_query
      schema.new_trace(
        mode: :persisted_tracer_mode,
      )
    elsif GitHub.flipper[:gql_field_tracer].enabled?(viewer) || gql_field_tracer
      schema.new_trace(
        mode: :field_tracer_mode,
        track_n_plus_one: GitHub.flipper[:gql_n_plus_one_tracer].enabled?(viewer)
      )
    else
      schema.new_trace(
        mode: :default_tracer_mode,
      )
    end
    # if we are using the OTEL tracer make sure we are setting the correct internal tracer
    # This is a temporary solution until this issue gets fixed:
    # https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/1126
    if tracer_instance.class.ancestors.include?(OpenTelemetry::Instrumentation::GraphQL::Tracers::GraphQLTrace)
      OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.instance_variable_set(
        :@tracer,
        OpenTelemetry.tracer_provider.tracer(
          "OpenTelemetry::Instrumentation::GraphQL",
          GraphQL::VERSION
        )
      )
    end
    tracer_instance
  end
  private_class_method :build_tracer

  # Scrub a user supplied GraphQL query given the query string and
  # optionally a Hash of variables for the query.
  #
  # query     - A String representing a GraphQL query.
  # variables - A String or a Hash representing the GraphQL query variables.
  #             If a String, must be JSON that can be parsed into a Hash.
  #
  # Returns a String representing the GraphQL query with any variables inlined
  # and scrubbed. Otherwise nil if there is any issue parsing or scrubbing the
  # query.
  sig { params(query: T.any(String, GraphQL::Query, GraphQL::Language::Nodes::Document)).returns(T.nilable(String)) }
  def self.scrubbed_query_for_context(query)
    Platform::Instrumentation::QueryPrinter.new(query).scrubbed
  rescue Platform::Instrumentation::QueryPrinter::InvalidQueryError
    nil # If it's an invalid query, just return nil
  rescue => e # rubocop:todo Lint/GenericRescue
    # Fail guard to make sure the sanitizer
    # handles all edge cases
    Failbot.report(e)
    nil
  end
  private_class_method :scrubbed_query_for_context

  sig do
    params(
      query: GraphQL::Query,
      origin: T.nilable(String),
      query_string: T.nilable(String),
      skip_scrubbing: T::Boolean
    )
      .returns(T.nilable(String))
  end
  def self.scrub_query(query:, origin: nil, query_string: nil, skip_scrubbing: false)
    if query_scrubbing_disabled? || origin == ORIGIN_INTERNAL || skip_scrubbing
      # Internal queries use variables and never
      # have user data hard coded in them, they are safe
      # to log and allow us to not validate the queries to use
      # with `QueryPrinter`
      query_string
    else
      scrubbed_query_for_context(query)
    end
  end
  private_class_method :scrub_query

  sig { params(hash: T::Hash[Symbol, T.untyped]).returns([IContext, IVariables]) }
  def self.extract_shorthand_arguments(hash)
    if hash.key?(:context) || hash.key?(:variables)
      raise KeyError, "It looks like you passed a :context or :variables key. This probably won't do what you want."
    end

    context = {}
    variables = {}

    hash.each_pair do |key, value|
      if key[0] == "$"
        variables[key[1..-1]] = value
      else
        context[key] = value
      end
    end

    [context, variables]
  end
  private_class_method :extract_shorthand_arguments

  sig { params(context: IContext).returns(IContext) }
  def self.extract_relevant_context_keys(context)
    {
      "gh.graphql.origin": context[:origin],
      # This is not a user-facing change so keep as login
      "gh.user.id": context[:viewer]&.id, # rubocop:disable GitHub/DoNotAllowLogin
      "gh.oauth.app.id": context[:oauth_app]&.id,
      "gh.integration.id": context[:integration]&.id,
      "enduser.scope": context[:granted_oauth_scopes],
    }
  end
  private_class_method :extract_relevant_context_keys

  # Public: Is the origin coming from a query GitHub wrote?
  #
  # Returns a Boolean.
  sig { params(origin: T.nilable(String)).returns(T::Boolean) }
  def self.safe_origin?(origin)
    origin == ORIGIN_MANUAL_EXECUTION || origin == ORIGIN_INTERNAL
  end

  # Public: Is the origin coming from the outside world?
  #
  # Returns a Boolean.
  sig { params(origin: String).returns(T::Boolean) }
  def self.unsafe_origin?(origin)
    !safe_origin?(origin)
  end

  # Public: Should stringent AuthZ checks be performed on queries coming from this origin?
  #
  # Returns a Boolean.
  sig { params(origin: String).returns(T::Boolean) }
  def self.requires_scope?(origin)
    origin == ORIGIN_API
  end

  sig { params(query: GraphQL::Query, exception: Exception).returns(T.nilable(String)) }
  def self.get_catalog_service_from_query(query:, exception:)
    current_field = query.context.namespace(:interpreter)[:current_field]

    # add special handling for persisted queries to get the owning service
    if query.context[:operation_id].present?
      if current_field.present?
        # check if the error was raised inside the auth function by looking at the stacktrace
        graphql_gem_regexp = /\/vendor\/gems\/[^\/]+\/ruby\/[^\/]+\/gems\/graphql/
        was_auth_error = if exception.backtrace.present?
          first_graphql_line = T.must(exception.backtrace).find { |line| line.match?(graphql_gem_regexp) } || ""
          # eg "/workspaces/github/vendor/gems/3.3.5/ruby/3.3.0/gems/graphql-2.3.10/lib/graphql/schema/object.rb:62:in `block in authorized_new'"
          first_graphql_line.end_with?("authorized_new'")
        else
          false
        end

        # check if we had an auth error and the object which was resolved had a service mapping
        if was_auth_error && current_field.type && current_field.type.service_mapping
          GitHub::ServiceMapping.catalog_service_name(current_field.type.service_mapping)
          # in this case we have an error that is not related to a field most likely a a loader
        elsif query.context[:current_catalog_service].present?
          query.context[:current_catalog_service]
        else
          GitHub::ServiceMapping.catalog_service_name(current_field.service_mapping)
        end
      else
        # no current field, this is most likely a top level error report to datadog
        tags = []
        tags << "operation_name:#{query.context[:query_name]}" if query.context[:query_name]
        tags << "gql_operation_name:#{query.context[:query_name]}" if query.context[:query_name]
        tags << "query_owning_catalog_service:#{query.context[:query_owning_catalog_service]}" if query.context[:query_owning_catalog_service]
        GitHub.dogstats.increment("platform.query.catalog_service_from_query.error", tags: tags)
        query.context[:current_catalog_service]
      end
    else
      query.context[:current_catalog_service]
    end
  end

  sig { params(query: GraphQL::Query, query_name: T.nilable(String), exception: Exception).void }
  def self.instrument_internal_errors(query:, query_name:, exception:)
    current_field = query.context.namespace(:interpreter)[:current_field]

    catalog_service = get_catalog_service_from_query(query:, exception:)

    tags = T.let([
      "catalog_service:#{catalog_service}",
      "operation_type:#{QueryTracker.operation_type_name(query)}",
    ], T::Array[String])
    tags += query.context[:reporting_tags] if query.context[:reporting_tags]
    tags << "operation_name:#{query_name}" if query_name
    tags << "gql_operation_name:#{query_name}" if query_name
    tags << "query_owning_catalog_service:#{query.context[:query_owning_catalog_service]}" if query.context[:query_owning_catalog_service]
    tags << "field:#{current_field.path}" if current_field
    if GitHub.flipper[:add_oauth_app_to_dog_tags].enabled? && query.context[:oauth_app]
      tags << get_oauth_tags(query.context[:oauth_app])
    end

    GitHub.dogstats.increment("platform.query.internal_error", tags: tags)
  end

  sig do
    params(exception: Exception, report_exceptions_to_failbot: T::Boolean, query: GraphQL::Query, query_name: T.nilable(String))
      .void
  end
  def self.report_internal_errors!(exception:, report_exceptions_to_failbot:, query:, query_name:)
    current_field = query.context.namespace(:interpreter)[:current_field]
    catalog_service = get_catalog_service_from_query(query:, exception:)

    interpreter_ns = query.context.namespace(:interpreter)
    runtime_failbot_ctx = {
      # assume graphql errors are all critical
      "gh.exception.is_critical": true
    }
    # `current_field` can be nil if an error comes from static validation (because the query isn't running yet)
    runtime_failbot_ctx[:"gh.graphql.current_field"] = current_field.path if current_field
    runtime_failbot_ctx[:"gh.graphql.current_path"] = interpreter_ns[:current_path] if interpreter_ns[:current_path]

    runtime_failbot_ctx[:catalog_service] = catalog_service if catalog_service
    # turn to downcase to match the reporting in datadog
    runtime_failbot_ctx[:"graphql.operation.name"] = query_name.downcase if query_name
    runtime_failbot_ctx[:"gh.graphql.catalog_service"] = query.context[:query_owning_catalog_service] if query.context[:query_owning_catalog_service]
    runtime_failbot_ctx.merge!(extract_failbot_context_from_reporting_tags(query))

    if report_exceptions_to_failbot
      Failbot.report(exception, runtime_failbot_ctx)
    else
      Failbot.push(runtime_failbot_ctx)
    end
  end

  sig { params(query: GraphQL::Query).returns(T::Hash[Symbol, T.untyped]) }
  def self.extract_failbot_context_from_reporting_tags(query)
    extract_reporting_tags(query).each_with_object({}) do |(tag_key, tag_value), result|
      tag_key = "gh.graphql.#{tag_key}" unless tag_key.to_s.start_with?("gh.graphql")
      tag_key = FAILBOT_TAG_KEY_MAPPING[tag_key.to_s] || tag_key

      result[tag_key.to_sym] = tag_value
    end
  end

  sig { params(query: GraphQL::Query).returns(T::Hash[Symbol, T.untyped]) }
  def self.extract_reporting_tags(query)
    result = {}

    if query.context[:reporting_tags]
      query.context[:reporting_tags].each do |tag|
        split_tag = tag.split(":", 2)
        next unless split_tag.length == 2

        (tag_key, tag_value) = split_tag
        result[tag_key.to_sym] = tag_value
      end
    end

    result
  end

  sig { params(query: GraphQL::Query).void }
  def self.instrument_errors!(query)
    span = GitHub.current_span
    shared_tags = T.let([], T::Array[String])
    shared_tags << "query_owning_catalog_service:#{query.context[:query_owning_catalog_service]}" if query.context[:query_owning_catalog_service]
    shared_tags += query.context[:reporting_tags] if query.context[:reporting_tags]
    if GitHub.flipper[:add_oauth_app_to_dog_tags].enabled? && query.context[:oauth_app]
      shared_tags << get_oauth_tags(query.context[:oauth_app])
    end

    query.validation_errors.each do |error|
      error_code = validation_error_code(error)
      tags = T.let(["type:validation", "code:#{error_code}"], T::Array[String])
      span.add_event("validation_error", attributes: { "gh.graphql.error.message" => error.to_s, "gh.graphql.error.type" => "validation", "gh.graphql.error.code" => error_code })
      GitHub.dogstats.increment("platform.query.runtime_error", tags: shared_tags + tags)
    end

    query.analysis_errors.each do |error|
      error_code = error_code(error)
      tags = T.let(["type:analysis", "code:#{error_code}"], T::Array[String])
      span.add_event("analysis_error", attributes: { "gh.graphql.error.message" => error.to_s, "gh.graphql.error.type" => "analysis", "gh.graphql.error.code" => error_code })
      GitHub.dogstats.increment("platform.query.runtime_error", tags: shared_tags + tags)
    end

    query.context.errors.each do |error|
      error_code = error_code(error)
      tags = T.let(["type:execution", "code:#{error_code}"], T::Array[String])
      span.add_event("execution_error", attributes: { "gh.graphql.error.message" => error.to_s, "gh.graphql.error.type" => "execution", "gh.graphql.error.code" => error_code })
      GitHub.dogstats.increment("platform.query.runtime_error", tags: shared_tags + tags)
    end
  end

  sig { params(error: T.any(GraphQL::Error, GraphQL::StaticValidation::Error)).returns(String) }
  def self.validation_error_code(error)
    code = T.let(nil, T.nilable(String))
    # Some special cases are from the GraphQL ruby gem (see validation_pipeline.rb
    # in the gem). These get added to the validation_errors array but do not come
    # from a root of StaticValidation::Error hence missing code information.
    code = if error.is_a?(GraphQL::StaticValidation::Error) && error.respond_to?(:code)
      # Only use T.unsafe if respond_to?(:code) is above
      T.unsafe(error).code.underscore
    elsif error.is_a? GraphQL::Query::OperationNameMissingError
      "operation_name_missing"
    elsif error.is_a? GraphQL::Query::VariableValidationError
      "variable_validation"
    end

    code || T.must(error.class.name).demodulize.downcase.underscore
  end
  private_class_method :validation_error_code

  sig { params(error: GraphQL::Error).returns(String) }
  def self.error_code(error)
    if error.respond_to?(:type)
      # Only use T.unsafe if respond_to? is above
      T.unsafe(error).type.downcase
    else
      T.must(error.class.name).demodulize.downcase.underscore
    end
  end
  private_class_method :error_code

  sig { returns(T::Boolean) }
  def self.query_scrubbing_disabled?
    # Disable query scrubbing by default in test mode since it can be expensive
    # for the large queries executed in authz and other tests
    Rails.env.test?
  end
  private_class_method :query_scrubbing_disabled?

  # In an effort to reduce costs, we won't send _every_ oauth app name to datadog.
  # We will just send a limited enum of oauth app related tags.
  sig { params(oauth_app: OauthApplication).returns(String) }
  def self.get_oauth_tags(oauth_app)
    prefix = "oauth_app:"

    prefix + if oauth_app.key == Apps::Privileged::Mobile::GITHUB_MOBILE_ANDROID_CLIENT_ID
      "mobile_android"
    elsif oauth_app.key == Apps::Privileged::Mobile::GITHUB_MOBILE_IOS_CLIENT_ID
      "mobile_ios"
    else
      "other"
    end
  end

  # We want to start tracking query names for queries from the mobile clients.
  # We will use this to keep costs low and not send query names for every query
  sig { params(oauth_app: T.nilable(OauthApplication)).returns(T::Boolean) }
  def self.should_track_query_name_for_oauth_app(oauth_app)
    oauth_app&.key == Apps::Privileged::Mobile::GITHUB_MOBILE_ANDROID_CLIENT_ID ||
      oauth_app&.key == Apps::Privileged::Mobile::GITHUB_MOBILE_IOS_CLIENT_ID
  end
end
