# typed: true
# frozen_string_literal: true

require "opentelemetry/instrumentation/graphql/tracers/graphql_trace"

module Platform
  class Schema < GraphQL::Schema
    use GraphQL::Pro::OperationStore, backend_class: Platform::OperationStore::ApplicationRecordBackend, update_last_used_at_every: 0
    context_class Context

    if GitHub.graphql_at_least_version("2.4")
      # forcing our visibility type checks
      use GraphQL::Schema::Warden

      # disable `DidYouMean...?` as suggested in here https://github.com/rmosolgo/graphql-ruby/pull/4966
      # TODO: once upgraded to graphql-ruby 2.4, remove sorbet/rbi/shims/app/platform/schema.rbi that is there
      # just to make Sorbet happy.
      GraphQL::Schema.did_you_mean(nil)
    end

    # remove the OperationStore instrumentation because we have alaready called it in Platform.execute
    new_tracers = self.tracers.reject do |t|
      t.is_a?(GraphQL::Pro::OperationStore::QueryInstrumentation)
    end
    instance_variable_set("@own_tracers", new_tracers)

    MAX_DEPTH = 25
    DEFAULT_MAX_PER_PAGE = 100
    ABSOLUTE_MAX_PER_PAGE = 250
    PROMISE_LAZY_METHOD_NAME = :sync
    INTERNAL_LAZY_METHOD_NAME = :value
    MAX_VALIDATION_TIMEOUT = 5
    MAX_VALIDATION_ERRORS = 50

    ORPHAN_TYPES = [
      Platform::Objects::CommitMention,
      Platform::Objects::GistComment,
      Platform::Objects::GpgSignature,
      Platform::Objects::SshSignature,
      Platform::Objects::Push,
      Platform::Objects::RepositoryInvitation,
      Platform::Objects::SmimeSignature,
      Platform::Objects::Tag,
      Platform::Objects::UnknownSignature,
      Platform::Objects::UserEmail,
      Platform::Objects::Enterprise,
      Platform::Objects::EnterpriseIdentityProvider,
      Platform::Objects::EnterpriseAdministratorInvitation,
      Platform::Objects::EnterpriseMemberInvitation,
      Platform::Objects::EnterpriseOrganizationInvitation,
      Platform::Objects::GenericHovercardContext,
      Platform::Objects::OrganizationsHovercardContext,
      Platform::Objects::OrganizationTeamsHovercardContext,
      Platform::Objects::ViewerHovercardContext,
      Platform::Objects::ReviewStatusHovercardContext,
      Platform::Objects::CheckRun,
      Platform::Objects::ValidationError,
      Platform::Objects::IpAllowListEntry,
      Platform::Objects::InternalRepositoryAdvisory,
      Platform::Objects::MobileSuggestedChange,
      Platform::Objects::UserListSuggestion,
      Platform::Objects::MergeConditions::PullRequestMergeConflictStateCondition,
      Platform::Objects::MergeConditions::PullRequestRepoStateCondition,
      Platform::Objects::MergeConditions::PullRequestRulesCondition,
      Platform::Objects::MergeConditions::PullRequestStateCondition,
      Platform::Objects::MergeConditions::PullRequestUserStateCondition,
      Platform::Objects::MergeConditions::PullRequestMergeMethodCondition,
      Platform::Objects::MemberFeatureRequestNotification,
      Platform::Objects::UserAsset,
      Platform::Objects::RepositoryFile,
    ].freeze

    EXTRA_TYPES = [
      Platform::Unions::OrganizationOrUser,
      Platform::Unions::BotOrUser,
    ].freeze

    PUBLIC_SHA = Digest::SHA256.hexdigest(File.read(Rails.root.join("config/schema.public.graphql")))
    INTERNAL_SHA = Digest::SHA256.hexdigest(File.read(Rails.root.join("config/schema.internal.graphql")))

    max_depth MAX_DEPTH
    validate_max_errors MAX_VALIDATION_ERRORS
    validate_timeout MAX_VALIDATION_TIMEOUT
    default_max_page_size DEFAULT_MAX_PER_PAGE

    def self.upcoming_changes(target: :internal, environment: GitHub.runtime.current.to_sym)
      Platform::Evolution::UpcomingChanges.new(
        self,
        target: target,
        environment: environment,
      )
    end

    def self.resolve_type(abstract_type, object, context)
      interpreter_ns = if context.respond_to?(:namespace)
        context.namespace(:interpreter)
      else
        {}
      end
      type_name = Platform::Helpers::NodeIdentification.type_name_from_object(object)
      Platform::Schema.get_type(type_name) || raise(KeyError) # rubocop:disable GitHub/UsePlatformErrors
    rescue KeyError, NoMethodError
      failbot_ctx = {}
      if interpreter_ns
        failbot_ctx[:"gh.graphql.current_field"] = interpreter_ns[:current_field].path if interpreter_ns[:current_field]
        failbot_ctx[:"gh.graphql.current_path"] = interpreter_ns[:current_path] if interpreter_ns[:current_path]
      end
      failbot_ctx[:catalog_service] = context[:current_catalog_service] if context[:current_catalog_service]
      # insert in the second to last position to avoid getting the context begin popped off
      position = if Failbot.context.size > 1
        Failbot.context.size - 1
      else
        0
      end
      Failbot.context.insert(position, failbot_ctx)

      raise Platform::Errors::Type, "Platform type '#{object.class}' is not defined."
    end

    # Modified version of GraphQL-Ruby's `DefaultTypeError`
    # graphql-ruby/lib/graphql/schema/default_type_error.rb
    def self.type_error(type_error, ctx)
      case type_error
      when GraphQL::InvalidNullError
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type_error.parent_type, ctx) do
          if Rails.env.production?
            # Replace invalid non null errors with an internal error instead
            # to not leak errors that are out of a client's control. However, we
            # still want to send them to failbot to fix the underlying issue.
            Failbot.report(type_error, { catalog_service: ctx[:current_catalog_service] })
            ctx.add_error(Platform::Errors::InternalExecution.new(type_error))
          else
            if GitHub.graphql_at_least_version("2.4")
              # related to fix https://github.com/rmosolgo/graphql-ruby/pull/5257
              # TODO: once upgraded to graphql-ruby 2.4, remove sorbet/rbi/shims/app/platform/schema.rbi that is there
              # just to make Sorbet happy.
              execution_error = GraphQL::ExecutionError.new(type_error.message, ast_node: type_error.ast_node)
              execution_error.path = ctx[:current_path]

              ctx.errors << execution_error
            else
              ctx.errors << type_error
            end
          end
        end
      when GraphQL::UnresolvedTypeError
        if type_error.resolved_type.required_capabilities.include?(:mobile_only_schema_mask) && Helpers::ProjectNext.is_project_next_api_type?(type_error.resolved_type)
          ctx.add_error(Errors::NotFound.new("#{Helpers::ProjectNext::DeprecationNotice[:reason]} #{Helpers::ProjectNext::DeprecationNotice[:superseded_by]}"))
        elsif type_error.resolved_type.visibility == [:internal] && Helpers::ProjectV2Events.is_project_v2_event_type?(type_error.resolved_type)
          ctx.add_error(Errors::NotFound.new)
        else
          raise type_error # rubocop:disable GitHub/UsePlatformErrors
        end
      when GraphQL::StringEncodingError
        raise type_error # rubocop:disable GitHub/UsePlatformErrors
      when GraphQL::IntegerEncodingError, GraphQL::IntegerDecodingError
        # Recent versions of GraphQL started raising with integers too large for the INT type.
        # To maintain backward compat, use the old behaviour (truncate)
        type_error.integer_value
      else
        raise Platform::Errors::Type, "Unexpected type_error #{type_error} during GraphQL Execution"
      end
    end

    def self.id_from_object(object, type, context)
      parsed_type = type.to_s.demodulize
      Platform::Helpers::GlobalId.async_for(object, parsed_type, **next_global_id_selection_from_context(context))
    end

    def self.object_from_id(id, context)
      Platform::Helpers::NodeIdentification.untyped_object_from_id( #rubocop: disable GitHub/UntypedObjectId
        id,
        permission: context[:permission],
        target: context[:target] || :internal
      ).then do |object|
        if object
          if context[:query_tracker]
            context[:query_tracker].fetched_node_id_types.add(
              id_version: Platform::Helpers::GlobalId.version(id),
              type_name: object.platform_type_name
            )

            record_access_for_object(context[:query_tracker], object)
          end

          if context[:tenant_tracker]
            context[:tenant_tracker].sync_log_query_tenant_context(object)
          end

          if Platform::Helpers::GlobalId.deprecated?(id, object) && (warnings = context[:warnings])
            # Sometimes this method is called without context, eg `NodeIdentification.typed_object_from_id`
            warnings.add(Platform::Warnings::DeprecatedGlobalId.new(object))
          end
          object
        else
          raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{id}'."
        end
      end
    end

    # Internal: Retrieve the next global ID selection criteria from the context or
    #           generates a default.
    #
    # context - The context.
    #
    # Returns a Hash.
    def self.next_global_id_selection_from_context(context)
      context[:global_id_selection] || {
        # Default values, when context details are not available
        user_preference: nil,
        user_opt_out: false,
      }
    end

    # Internal: serialize specific objects to the query tracker for customer attribution requirements.
    #
    # This currently targets only repositories, users/organizations and businesses.
    def self.record_access_for_object(query_tracker, object)
      object_for_serialization = if object.is_a?(::User)
        { database_id: object.id, ruby_class_name: "User", global_relay_id: object.global_relay_id, graphql_name: "User" }
      elsif object.is_a?(::Organization)
        { database_id: object.id, ruby_class_name: "Organization", global_relay_id: object.global_relay_id, graphql_name: "Organization" }
      elsif object.is_a?(::Business)
        { database_id: object.id, ruby_class_name: "Business", global_relay_id: object.global_relay_id, graphql_name: "Business" }
      elsif object.is_a?(::Repository)
        { database_id: object.id, ruby_class_name: "Repository", global_relay_id: object.global_relay_id, graphql_name: "Repository" }
      end

      return unless object_for_serialization

      query_tracker.accessed_objects[[object.class, object_for_serialization]] ||= object_for_serialization
    end

    # Performance optimization because we know our only
    # lazy objects are promises besides graphql-ruby internal obj
    def lazy_method_name(obj)
      case obj
      when GraphQL::Execution::Lazy
        INTERNAL_LAZY_METHOD_NAME
      when Promise
        PROMISE_LAZY_METHOD_NAME
      else
        nil
      end
    end

    query Platform::Objects::Query
    mutation Platform::Objects::Mutation
    subscription Platform::Objects::EventSubscription

    use Platform::AliveSubscriptions

    orphan_types ORPHAN_TYPES
    extra_types EXTRA_TYPES

    DEFAULT_TRACER_MODES = [
      :default_tracer_mode,
      :performance_trace_mode,
      :field_tracer_mode,
      :field_latency_tracer_mode,
      # Although it is temporary, adding this here allows the other OTEL and rate limiting tracers to run alongside this
      :sub_issue_tracing_mode,
    ].freeze
    # Activate GraphQL::Batch loading for tracer modes
    trace_with(Platform::Batch::Setup::Trace)
    trace_with(Platform::Tracing::NullTracer)
    lazy_resolve(::Promise, :sync)

    trace_with(Platform::SubIssueFieldTracer, mode: :sub_issue_tracing_mode)
    trace_with(Platform::Tracing::FieldLatencyTracer, mode: :sub_issue_tracing_mode)

    trace_with(Platform::Tracing::NullTracer, mode: :persisted_tracer_mode)

    trace_with(OpenTelemetry::Instrumentation::GraphQL::Tracers::GraphQLTrace, mode: :persisted_tracer_debug_mode)
    trace_with(Platform::PersistedQueryTracer, mode: :persisted_tracer_debug_mode)
    trace_with(Platform::Tracing::FieldTracer, mode: :persisted_tracer_debug_mode)

    # Add the basic tracers to the default modes
    trace_with(Platform::RateLimitRequest::Trace, mode: DEFAULT_TRACER_MODES)
    trace_with(OpenTelemetry::Instrumentation::GraphQL::Tracers::GraphQLTrace, mode: DEFAULT_TRACER_MODES)
    trace_with(Platform::Tracing::MapToService, mode: DEFAULT_TRACER_MODES)

    # these special tracer modes are used for specific tracers
    trace_with(Platform::PerformancePaneTracer, mode: :performance_trace_mode)
    trace_with(Platform::Tracing::FieldTracer, mode: :field_tracer_mode)

    #This mode tracks service+field latency without MySQL times
    trace_with(Platform::Tracing::FieldLatencyTracer, mode: :field_latency_tracer_mode)

    connections.add(ActiveRecord::Relation, Platform::ConnectionWrappers::Relation)
    connections.add(Platform::StableArrayWrapper, Platform::ConnectionWrappers::StableArray)
    connections.add(Platform::ArrayWrapper, Platform::ConnectionWrappers::ArrayWrapper)
    connections.add(Platform::Wrappers::RemoteProxyRelation, Platform::ConnectionWrappers::RemoteRelation)
    connections.add(Platform::Helpers::NotificationThreadsQuery, Platform::ConnectionWrappers::Notifications)
    connections.add(Platform::Helpers::NotificationsQuery, Platform::ConnectionWrappers::Notifications)
    connections.add(Platform::ExperimentRelation, Platform::ConnectionWrappers::ExperimentRelation)
    connections.add(Platform::Helpers::ProjectsQuery, Platform::ConnectionWrappers::ElasticSearchQuery)
    connections.add(Platform::Helpers::IssuesQuery, Platform::ConnectionWrappers::ElasticSearchQuery)
    connections.add(Audit::Driftwood::Query, Platform::ConnectionWrappers::DriftwoodQuery)
    connections.add(Search::Queries::AuditLogQuery, Platform::ConnectionWrappers::AuditLogQuery)
    connections.add(Search::Queries::StafftoolsQuery, Platform::ConnectionWrappers::AuditLogQuery)
    connections.add(Search::Queries::ConditionalIssueQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::ConditionalIssueSemanticQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::IssueQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::IssueSemanticQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::RepoQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::UserQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::UserLoginQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::MarketplaceQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::LabelQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Search::Queries::DiscussionQuery, Platform::ConnectionWrappers::SearchQuery)
    connections.add(Platform::Helpers::WatchersQuery, Platform::ConnectionWrappers::Newsies)
    connections.add(Platform::Helpers::WatchingQuery, Platform::ConnectionWrappers::Newsies)
    connections.add(Issues::Timeline::Timeline, Platform::ConnectionWrappers::TimelineItems)
    connections.add(Platform::Helpers::TimelineWrapper, Platform::ConnectionWrappers::Timeline)
    connections.add(GH::Domain::CursorCollection, Platform::ConnectionWrappers::CursorCollection)

    # add in custom directives
    directive(Platform::Directives::Defer)
    directive(Platform::Directives::Stream)

    query_analyzer(Platform::Analyzers::QueryCoster)
    query_analyzer(Platform::Analyzers::LimitIntrospection)
    query_analyzer(Platform::Analyzers::MinimumAcceptedScopes)
    query_analyzer(Platform::Analyzers::QueryComplexity)
    query_analyzer(Platform::Analyzers::QueryDepth)
    query_analyzer(Platform::Analyzers::LimitAliasSize)

    include Platform::RuntimeErrors
  end
end
