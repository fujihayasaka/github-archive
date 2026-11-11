# typed: strict
# frozen_string_literal: true

require "time"

module Api::App::ActionsDataStreamSinksHelper
  extend T::Helpers
  requires_ancestor { Api::App }

  include Api::App::ErrorDependency
  include Api::App::DeliveryDependency
  include Api::App::InputDependency
  include Api::App::TwirpHelpers

  OWNER_TYPE_PARAM_MAP = T.let({
    enterprise: :OWNER_TYPE_ENTERPRISE,
    organization: :OWNER_TYPE_ORGANIZATION,
  }.freeze, T::Hash[Symbol, Symbol])

  SINK_TYPE_PARAM_MAP = T.let({
    "s3" => :SINK_TYPE_S3,
    "azure_blob" => :SINK_TYPE_AZURE_BLOB,
    "azure_kusto" => :SINK_TYPE_AZURE_KUSTO,
    "aws_firehose" => :SINK_TYPE_AWS_FIREHOSE,
    "azure_event_hub" => :SINK_TYPE_AZURE_EVENT_HUB,
  }.freeze, T::Hash[String, Symbol])

  SINK_STATUS_PARAM_MAP = T.let({
    "active" => :SINK_STATUS_ACTIVE,
    "paused" => :SINK_STATUS_PAUSED,
    "disabled" => :SINK_STATUS_DISABLED,
    "error" => :SINK_STATUS_ERROR,
  }.freeze, T::Hash[String, Symbol])

  ENUM_VALUE_MAP = T.let({
    owner_type: {
      1 => "enterprise",
      2 => "organization",
    },
    sink_type: {
      1 => "s3",
      2 => "azure_blob",
      3 => "azure_kusto",
      6 => "aws_firehose",
      7 => "azure_event_hub",
    },
    sink_status: {
      1 => "active",
      2 => "paused",
      3 => "disabled",
      4 => "error",
    },
    health_status: {
      1 => "healthy",
      2 => "degraded",
      3 => "unhealthy",
    },
  }.freeze, T::Hash[Symbol, T::Hash[Integer, String]])

  ENUM_PREFIX_MAP = T.let({
    owner_type: "OWNER_TYPE_",
    sink_type: "SINK_TYPE_",
    sink_status: "SINK_STATUS_",
    health_status: "HEALTH_STATUS_",
  }.freeze, T::Hash[Symbol, String])

  sig { params(owner: T.untyped, owner_type: Symbol).returns(T.untyped) }
  def actions_data_stream_list_sinks!(owner:, owner_type:)
    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).list_sinks(**actions_data_stream_owner_arguments(owner:, owner_type:))
    end

    deliver_raw(actions_data_stream_sinks_hash(response&.sinks || []))
  end

  sig { params(owner: T.untyped, owner_type: Symbol, sink_id: T.untyped).returns(T.untyped) }
  def actions_data_stream_get_sink!(owner:, owner_type:, sink_id:)
    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).get_sink(**actions_data_stream_owner_arguments(owner:, owner_type:), id: sink_id)
    end

    deliver_raw(actions_data_stream_sink_hash(response&.sink))
  end

  sig { params(owner: T.untyped, owner_type: Symbol, name: String).returns(T.untyped) }
  def actions_data_stream_get_sink_by_name!(owner:, owner_type:, name:)
    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).get_sink_by_name(**actions_data_stream_owner_arguments(owner:, owner_type:), name: name)
    end

    deliver_raw(actions_data_stream_sink_hash(response&.sink))
  end

  sig { params(owner: T.untyped, owner_type: Symbol).returns(T.untyped) }
  def actions_data_stream_create_sink!(owner:, owner_type:)
    attributes = actions_data_stream_create_attributes!(receive_with_openapi.to_h.stringify_keys)
    owner_args = actions_data_stream_owner_arguments(owner:, owner_type:)

    test_response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).test_sink(
        **owner_args,
        create_sink_request: {
          **owner_args,
          **attributes,
        },
      )
    end

    unless test_response&.success
      return deliver_raw(actions_data_stream_test_result_hash(test_response), status: 422)
    end

    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).create_sink(**owner_args, **attributes)
    end

    deliver_raw(actions_data_stream_sink_hash(response&.sink), status: 201)
  end

  sig { params(owner: T.untyped, owner_type: Symbol, sink_id: T.untyped).returns(T.untyped) }
  def actions_data_stream_update_sink!(owner:, owner_type:, sink_id:)
    attributes = actions_data_stream_update_attributes!(receive_with_openapi.to_h.stringify_keys)
    owner_args = actions_data_stream_owner_arguments(owner:, owner_type:)

    if attributes.key?(:config)
      existing_response = handle_twirp_errors do
        T.unsafe(ActionsDataStream::Twirp.sink_client).get_sink(**owner_args, id: sink_id)
      end

      existing_sink = existing_response&.sink
      existing_config = existing_sink&.config&.to_h || {}
      merged_config = Google::Protobuf::Struct.from_hash(existing_config.merge(attributes[:config].to_h))
      test_attributes = {
        name: attributes[:name] || existing_sink&.name || "",
        sink_type: existing_sink&.sink_type,
        config: merged_config,
      }

      test_response = handle_twirp_errors do
        T.unsafe(ActionsDataStream::Twirp.sink_client).test_sink(
          **owner_args,
          create_sink_request: {
            **owner_args,
            **test_attributes,
          },
        )
      end

      unless test_response&.success
        return deliver_raw(actions_data_stream_test_result_hash(test_response), status: 422)
      end
    end

    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).update_sink(**owner_args, id: sink_id, **attributes)
    end

    deliver_raw(actions_data_stream_sink_hash(response&.sink), status: 200)
  end

  sig { params(owner: T.untyped, owner_type: Symbol, sink_id: T.untyped).returns(T.untyped) }
  def actions_data_stream_delete_sink!(owner:, owner_type:, sink_id:)
    handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).delete_sink(**actions_data_stream_owner_arguments(owner:, owner_type:), id: sink_id)
    end

    deliver_empty status: 204
  end

  private

  sig { params(owner: T.untyped, owner_type: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def actions_data_stream_owner_arguments(owner:, owner_type:)
    {
      owner_type: OWNER_TYPE_PARAM_MAP.fetch(owner_type),
      owner_id: owner.id,
    }
  end

  sig { params(sinks: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def actions_data_stream_sinks_hash(sinks)
    {
      total_count: sinks.size,
      sinks: sinks.map { |sink| actions_data_stream_sink_hash(sink) },
    }
  end

  sig { params(sink: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def actions_data_stream_sink_hash(sink)
    return nil unless sink

    {
      id: sink.id,
      owner_type: actions_data_stream_enum_value(:owner_type, sink.owner_type),
      owner_id: sink.owner_id,
      name: sink.name,
      sink_type: actions_data_stream_enum_value(:sink_type, sink.sink_type),
      status: actions_data_stream_enum_value(:sink_status, sink.status),
      config: sink.config&.to_h || {},
      sink_health: actions_data_stream_sink_health_hash(sink.sink_health),
    }.compact
  end

  sig { params(sink_health: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def actions_data_stream_sink_health_hash(sink_health)
    return nil unless sink_health

    {
      health_status: actions_data_stream_enum_value(:health_status, sink_health.health_status),
      last_success_at: actions_data_stream_timestamp(sink_health.last_success_at),
      last_failure_at: actions_data_stream_timestamp(sink_health.last_failure_at),
      last_error: sink_health.last_error.presence,
      consecutive_failures: sink_health.consecutive_failures,
      checked_at: actions_data_stream_timestamp(sink_health.checked_at),
    }.compact
  end

  sig { params(timestamp: T.untyped).returns(T.nilable(String)) }
  def actions_data_stream_timestamp(timestamp)
    return nil unless timestamp

    seconds = timestamp.respond_to?(:seconds) ? timestamp.seconds : nil
    nanos = timestamp.respond_to?(:nanos) ? timestamp.nanos.to_i : 0
    return nil if seconds.nil? || (seconds.zero? && nanos.zero?)

    Time.at(seconds, nanos, :nanosecond).utc.iso8601
  end

  sig { params(type: Symbol, value: T.untyped).returns(T.nilable(String)) }
  def actions_data_stream_enum_value(type, value)
    return nil if value.nil?

    ENUM_VALUE_MAP.fetch(type).fetch(value) do
      actions_data_stream_normalize_enum(type, value)
    end
  end

  sig { params(type: Symbol, value: T.untyped).returns(T.nilable(String)) }
  def actions_data_stream_normalize_enum(type, value)
    string_value = value.to_s
    prefix = ENUM_PREFIX_MAP.fetch(type)
    return nil unless string_value.start_with?(prefix)

    string_value.delete_prefix(prefix).downcase
  end

  sig { params(data: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def actions_data_stream_create_attributes!(data)
    {
      name: actions_data_stream_required_string!(data, "name"),
      sink_type: actions_data_stream_sink_type!(data["sink_type"]),
      config: actions_data_stream_config!(data["config"]),
    }
  end

  sig { params(data: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def actions_data_stream_update_attributes!(data)
    attributes = {}

    if data.key?("name")
      attributes[:name] = actions_data_stream_required_string!(data, "name")
    end

    if data.key?("status")
      attributes[:status] = actions_data_stream_sink_status!(data["status"])
    end

    if data.key?("config")
      attributes[:config] = actions_data_stream_config!(data["config"])
    end

    if attributes.empty?
      deliver_error! 422, message: "At least one of name, status, or config must be provided."
    end

    attributes
  end

  sig { params(data: T::Hash[String, T.untyped], key: String).returns(String) }
  def actions_data_stream_required_string!(data, key)
    value = data[key]
    unless value.is_a?(String) && value.present?
      deliver_error! 422, message: "#{key} must be a non-empty string."
    end

    value
  end

  sig { params(value: T.untyped).returns(Symbol) }
  def actions_data_stream_sink_type!(value)
    enum_value = SINK_TYPE_PARAM_MAP[value]
    return enum_value if enum_value

    deliver_error! 422, message: "sink_type must be one of: #{SINK_TYPE_PARAM_MAP.keys.join(", ")}."
  end

  sig { params(value: T.untyped).returns(Symbol) }
  def actions_data_stream_sink_status!(value)
    enum_value = SINK_STATUS_PARAM_MAP[value]
    return enum_value if enum_value

    deliver_error! 422, message: "status must be one of: #{SINK_STATUS_PARAM_MAP.keys.join(", ")}."
  end

  sig { params(value: T.untyped).returns(Google::Protobuf::Struct) }
  def actions_data_stream_config!(value)
    if value.is_a?(Hash)
      Google::Protobuf::Struct.from_hash(value)
    else
      deliver_error! 422, message: "config must be an object."
    end
  end

  sig { params(owner: T.untyped, owner_type: Symbol, sink_id: T.untyped).returns(T.untyped) }
  def actions_data_stream_test_sink!(owner:, owner_type:, sink_id:)
    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).test_sink(
        **actions_data_stream_owner_arguments(owner:, owner_type:),
        sink_id: sink_id,
      )
    end

    deliver_raw(actions_data_stream_test_result_hash(response))
  end

  sig { params(owner: T.untyped, owner_type: Symbol).returns(T.untyped) }
  def actions_data_stream_test_sink_new!(owner:, owner_type:)
    attributes = actions_data_stream_create_attributes!(receive_with_openapi.to_h.stringify_keys)
    owner_args = actions_data_stream_owner_arguments(owner:, owner_type:)

    response = handle_twirp_errors do
      T.unsafe(ActionsDataStream::Twirp.sink_client).test_sink(
        **owner_args,
        create_sink_request: {
          **owner_args,
          **attributes,
        },
      )
    end

    deliver_raw(actions_data_stream_test_result_hash(response))
  end

  sig { params(response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def actions_data_stream_test_result_hash(response)
    {
      success: response&.success || false,
      error_message: response&.error_message.presence || "",
      status_code: response&.status_code || 0,
      latency_ms: response&.latency_ms || 0,
    }
  end
end
