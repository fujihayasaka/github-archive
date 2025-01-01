# typed: strict
# frozen_string_literal: true

module Platform
  class Context < GraphQL::Query::Context
    KNOWN_INITIALIZE_KEYS = T.let([
      :action,
      :actor,
      :actor_ip,
      :allow_errors,
      :anonymous_viewer,
      :anonymous_viewer_query_allowlist,
      :auth_fingerprint,
      :authenticated_actor_using_web_session,
      :backwards_compatibility_pending,
      :base_ip_request,
      :block_mutations,
      :cap_exclude_policies,
      :cap_filter,
      :catalog_services,
      :changeset_version,
      :client_permits_replicas,
      :controller,
      :cost_limiter,
      :current_catalog_service,
      :current_client_name,
      :dataloader,
      :defer,
      :enforce_conditional_access_via_graphql,
      :entities_for_oauth_access,
      :entity_for_oauth_access,
      :error_reported,
      :feature_flags,
      :force_readonly,
      :force_readonly_primary,
      :forwarded_for,
      :global_id_selection,
      :granted_oauth_scopes,
      :graphql_batch_executor,
      :graphql_global_id_type,
      :installation,
      :integration,
      :internal_api_host,
      :internal_error,
      :internal_ip_request,
      :interpreter_instance,
      :ip,
      :is_internal_graphql,
      :is_mirrored_request, # Traffic mirroring
      :is_relay_request,
      :log_data,
      :mask,
      :mobile_only,
      :oauth_app,
      :object,
      :operation_id,
      :operation_name,
      :origin,
      :performance_trace,
      :performance_trace_field_profile_path,
      :performance_trace_field_profile_type,
      :permission,
      :query_name,
      :query_owning_catalog_service,
      :query_string,
      :query_tracker,
      :rails_request,
      :raise_exceptions,
      :rate_limit_configuration,
      :rate_limit_dry_run,
      :real_ip,
      :records,
      :reporting_tags,
      :request_access_security_header,
      :request_client_ip,
      :request_context,
      :request_hmac,
      :request_id,
      :request_token,
      :response,
      :role,
      :run_defer_directive,
      :scope,
      :scope_object,
      :scoped_repo_id,
      :scrubbed_query,
      :serialize_login,
      :session,
      :target,
      :tenant_tracker,
      :to,
      :trace,
      :trace_mode,
      :tracers,
      :track_query_name,
      :unauthorized_organization_ids,
      :unfurl_references,
      :user_agent,
      :user_session,
      :viewer,
      :warnings,
    ], T::Array[Symbol])

    ALLOWED_SETTER_KEYS = T.let([
      :__pro_access_strategy__,
      :backwards_compatibility_pending,
      :catalog_services,
      :cost_breakdowns,
      :cost_total,
      :current_arguments,
      :current_catalog_service,
      :current_field,
      :current_object,
      :current_path,
      :dataloader,
      :defer,
      :entities_for_oauth_access,
      :entity_for_oauth_access,
      :error_reported,
      :graphql_batch_executor,
      :graphql_global_id_type,
      :index_entries,
      :internal_error,
      :interpreter_instance,
      :invalid_user_errors,
      :last_ip_spam_patterns_regexp,
      :mask,
      :mutation_name,
      :node_count_breakdowns,
      :node_count_total,
      :object,
      :permission,
      :query_string,
      :query_tracker,
      :raise_exceptions,
      :rate_limit_dry_run,
      :read_arguments_from_replicas,
      :recalculate_sub_issues_summary_issue_id,
      :run_defer_directive,
      :scoped_repo_id,
      :scrubbed_query_string,
      :subscription_id,
      :tenant_tracker,
    ], T::Array[Symbol])

    ALLOWED_GETTER_KEYS = T.let([
      :action,
      :actor,
      :anonymous_viewer_query_allowlist,
      :auth_fingerprint,
      :authenticated_actor_using_web_session,
      :backtrace,
      :backwards_compatibility_pending,
      :base_ip_request,
      :block_mutations,
      :cap_exclude_policies,
      :cap_filter,
      :catalog_service,
      :catalog_services,
      :client_permits_replicas,
      :controller,
      :cost_breakdowns,
      :cost_limiter,
      :cost_total,
      :current_arguments,
      :current_catalog_service,
      :current_field,
      :current_object,
      :current_path,
      :dataloader,
      :defer,
      :enforce_conditional_access_via_graphql,
      :entities_for_oauth_access,
      :entity_for_oauth_access,
      :error_reported,
      :feature_flags,
      :forwarded_for,
      :global_id_selection,
      :granted_oauth_scopes,
      :graphql_batch_executor,
      :graphql_global_id_type,
      :index_entries,
      :installation,
      :integration,
      :internal_api_host,
      :internal_error,
      :internal_errors,
      :internal_ip_request,
      :interpreter_instance,
      :invalid_user_errors,
      :ip,
      :is_mirrored_request, # Traffic mirroring
      :last_ip_spam_patterns_regexp,
      :log_data,
      :mask,
      :mutation_name,
      :node_count_breakdowns,
      :node_count_total,
      :oauth_app,
      :object,
      :operation_id,
      :operation_name,
      :origin,
      :performance_trace,
      :permission,
      :query_complexity,
      :query_depth,
      :query_name,
      :query_owning_catalog_service,
      :query_string,
      :query_tracker,
      :rails_request,
      :raise_exceptions,
      :rate_limit_dry_run,
      :read_arguments_from_replicas,
      :real_ip,
      :recalculate_sub_issues_summary_issue_id,
      :records,
      :reporting_tags,
      :request_access_security_header,
      :request_client_ip,
      :request_context,
      :request_hmac,
      :request_id,
      :request_token,
      :response,
      :run_defer_directive,
      :scope,
      :scope_object,
      :scoped_repo_id,
      :scrubbed_query,
      :serialize_login,
      :subscription_id,
      :target,
      :tenant_tracker,
      :trace,
      :trace_mode,
      :tracers,
      :track_query_name,
      :unauthorized_organization_ids,
      :user_agent,
      :user_session,
      :viewer,
      :warnings,
    ], T::Array[Symbol])

    sig { returns(T::Boolean) }
    def self.enforce_known_keys?
      # Enforcement is currently disable by default and in tests it is enabled with a global stub.
      false
    end

    sig do
      params(
        query: T.any(T.nilable(GraphQL::Query), T::Hash[Symbol, T.untyped]),
        schema: T.untyped,
        values: T.nilable(T::Hash[Symbol, T.untyped]),
      )
        .void
    end
    def initialize(query:, schema: nil, values: nil)
      if !self.class.enforce_known_keys? || unknown_initialize_keys(values).empty?
        schema ||= T.cast(query, GraphQL::Query).schema
        args = { query: query, schema: schema, values: values }
        super(**args)
      else
        raise Platform::Errors::ArgumentError, "Initializing context with unknown values '#{unknown_initialize_keys(values).join(', ')}'"
      end
    end

    sig { params(key: Symbol).returns(T.untyped) }
    def [](key)
      return super if !self.class.enforce_known_keys? || ALLOWED_GETTER_KEYS.include?(key)

      raise Platform::Errors::ArgumentError, "Getting unknown value '#{key}' from context"
    end

    sig { params(key: Symbol, value: T.untyped).void }
    def []=(key, value)
      return super if !self.class.enforce_known_keys? || ALLOWED_SETTER_KEYS.include?(key)

      raise Platform::Errors::ArgumentError, "Setting unknown value '#{key}' from context"
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      return super if !self.class.enforce_known_keys?

      raise Platform::Errors::ArgumentError, "Don't use to_h. It makes it impossible to track used keys."
    end

    private

    sig { params(values: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Array[Symbol]) }
    def unknown_initialize_keys(values)
      (values || {}).keys - KNOWN_INITIALIZE_KEYS
    end
  end
end
