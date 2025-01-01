# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("platform.query") do |payload, _event_name|
    origin = case payload[:origin]
    when Platform::ORIGIN_INTERNAL
      :INTERNAL
    when Platform::ORIGIN_API
      :GRAPHQL_API
    when Platform::ORIGIN_REST_API
      :REST_API
    when Platform::ORIGIN_MANUAL_EXECUTION
      :MANUAL_EXECUTION
    else
      :ORIGIN_UNKNOWN
    end

    target = case payload[:target]
    when :public
      :PUBLIC_SCHEMA
    when :internal
      :INTERNAL_SCHEMA
    else
      :TARGET_UNKOWN
    end

    operation_type = case payload[:operation_type]
    when "query"
      :QUERY
    when "mutation"
      :MUTATION
    when "subscription"
      :SUBSCRIPTION
    else
      :UNKNOWN_OPERATION_TYPE
    end

    # Traffic mirroring
    traffic_mirroring = case payload[:traffic_mirroring]
    when :control
      :CONTROL
    when :candidate
      :CANDIDATE
    when :not_mirrored
      :NOT_MIRRORED
    else
      :UNKNOWN
    end

    request_context = serializer.request_context(GitHub.context.to_hash)
    request_id = payload[:request_id] || (request_context[:request_id] if request_context)

    additional_metrics = {}
    potential_corrected_parent_request_count = payload[:potential_corrected_parent_request_count]
    if potential_corrected_parent_request_count
      additional_metrics["potential_corrected_parent_request_count"] = potential_corrected_parent_request_count.to_s
    end

    bypass_query_coster_parent_request_count_changes = payload[:bypass_query_coster_parent_request_count_changes]
    if bypass_query_coster_parent_request_count_changes
      additional_metrics["bypass_query_coster_parent_request_count_changes"] = bypass_query_coster_parent_request_count_changes.to_s
    end

    if payload[:query_depth]
      additional_metrics["query_depth"] = payload[:query_depth].to_s
    end

    message = {
      request_context: request_context,
      app: serializer.app(payload[:app]),
      viewer: serializer.user(payload[:viewer]),
      query_string: payload[:query_string],
      origin: origin,
      target: target,
      schema_version: payload[:schema_version],
      dotcom_sha: payload[:dotcom_sha],
      selected_operation: payload[:selected_operation],
      operation_type: operation_type,
      valid: payload[:valid],
      errors: payload[:errors],
      accessed_objects: payload[:accessed_objects].map { |o| serializer.graphql_accessed_object(o) }.uniq,
      query_hash: payload[:query_hash],
      variables_hash: payload[:variables_hash],
      cpu_time_ms: payload[:cpu_time_ms],
      idle_time_ms: [payload[:idle_time_ms].to_i, 0].max,
      mysql_count: payload[:mysql_count],
      mysql_time_ms: payload[:mysql_time_ms],
      gitrpc_count: payload[:gitrpc_count],
      gitrpc_time_ms: payload[:gitrpc_time_ms],
      timed_out: payload[:timed_out],
      node_count: payload[:node_count],
      request_count: payload[:request_count],
      complexity_cost: payload[:complexity_cost],
      length_of_largest_alias: payload[:length_of_largest_alias],
      fetched_node_id_types: payload[:fetched_node_id_types],
      request_id: request_id,
      graphql_global_id_type: payload[:graphql_global_id_type],
      graphql_operation_id: payload[:graphql_operation_id],
      query_byte_size: payload[:query_byte_size],
      variables_byte_size: payload[:variables_byte_size],
      query_owning_catalog_service: payload[:query_owning_catalog_service],
      traffic_mirroring: traffic_mirroring, # Traffic mirroring
      result_byte_size: payload[:result_byte_size], # Traffic mirroring
      result_hash: payload[:result_hash], # Traffic mirroring
      elastomer_query_count: payload[:elastomer_query_count],
      elastomer_query_time_ms: payload[:elastomer_query_time_ms],
      metrics_by_service: payload[:metrics_by_service],
      integration_installation_value: serializer.integration_installation_for_graphql(payload[:installation]),
      primary_rate_limited: payload[:primary_rate_limited],
      auth_fingerprint: payload[:auth_fingerprint],
      referrer_controller_action: payload[:referrer_controller_action],
      additional_metrics: additional_metrics, # Use this for any additional metrics you want to include in the event, useful for anything temporary or experimental
      spokes_time_ms: payload[:spokes_time_ms],
    }

    message.merge!({
      authzd_batch_authorize_count: payload[:authzd_batch_authorize_count],
      authzd_batch_authorize_time_ms: payload[:authzd_batch_authorize_time_ms]
    })

    publish(message, schema: "github.v1.GraphQLQuery", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
