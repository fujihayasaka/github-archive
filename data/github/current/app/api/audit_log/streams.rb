# typed: true
# frozen_string_literal: true

class Api::AuditLog::Streams < Api::App
  include Api::AuditLog::Helpers
  include FeatureFlagHelper

  class NoMatchFoundError < StandardError; end
  class SinkError < StandardError; end

  STREAM_TYPE_MAPPING = {
    "Azure Blob Storage" => {
      model: AuditLogAzureBlobSinkConfiguration,
      permitted_params: [:key_id, :encrypted_sas_url],
    },
    "Azure Event Hubs" => {
      model: AuditLogAzureHubsSinkConfiguration,
      permitted_params: [:name, :encrypted_connstring, :key_id],
    },
    "Amazon S3" => {
      model: AuditLogS3SinkConfiguration,
      permitted_params: [:region, :encrypted_access_key_id, :encrypted_secret_key, :arn_role, :key_id, :authentication_type, :bucket],
    },
    "Splunk" => {
      model: AuditLogSplunkSinkConfiguration,
      permitted_params: [:domain, :port, :encrypted_token, :ssl_verify, :key_id],
    },
    "HTTPS Event Collector" => {
      model: AuditLogHecSinkConfiguration,
      permitted_params: [:domain, :port, :encrypted_token, :path, :ssl_verify, :key_id],
    },
    "Google Cloud Storage" => {
      model: AuditLogGoogleCloudSinkConfiguration,
      permitted_params: [:key_id, :bucket, :encrypted_json_credentials],
    },
    "Datadog" => {
      model: AuditLogDatadogSinkConfiguration,
      permitted_params: [:encrypted_token, :site, :key_id],
    },
  }.freeze

  get "/enterprises/:enterprise_id/audit-log/streams", operation_id: "enterprise-admin/get-audit-log-streams" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)

    control_access :list_audit_log_streams,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    streams = find_audit_log_stream_configurations!

    begin
      streams_hash = bundle_audit_log_stream(streams)
      deliver_raw(streams_hash, status: 200)
    rescue NoMatchFoundError => e
      deliver_error 404, message: e
    end
  end


  get "/enterprises/:enterprise_id/audit-log/stream-key", operation_id: "enterprise-admin/get-audit-log-stream-key" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)

    key_id = GitHub.driftwood_stream_key_id
    key = GitHub.driftwood_stream_key

    control_access :get_audit_log_stream_key,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    begin
      res = {
        key_id: key_id,
        key: key
      }
      deliver_raw(res, status: 200)
    rescue NoMatchFoundError => e
      deliver_error 404, message: e
    end
  end


  get "/enterprises/:enterprise_id/audit-log/streams/:stream_id", operation_id: "enterprise-admin/get-one-audit-log-stream" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)
    stream = find_audit_log_stream_configurations!

    control_access :list_audit_log_streams,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    begin
      stream_hash = bundle_audit_log_stream(stream)
      deliver_raw(stream_hash, status: 200)
    rescue NoMatchFoundError => e
      deliver_error 404, message: e
    end
  end

  delete "/enterprises/:enterprise_id/audit-log/streams/:stream_id", operation_id: "enterprise-admin/delete-audit-log-stream" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)

    control_access :delete_audit_log_stream,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    stream = find_audit_log_stream_configurations!

    begin
      stream.destroy
      deliver_empty status: 204
    rescue NoMatchFoundError => e
      deliver_error 404, message: e
    end
  end

  put "/enterprises/:enterprise_id/audit-log/streams/:stream_id", operation_id: "enterprise-admin/update-audit-log-stream" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)
    stream = find_audit_log_stream_configurations!

    control_access :edit_audit_log_stream,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    data = receive_with_openapi

    deliver_error! 404 if data["stream_type"].downcase != stream.sink.sink_type.downcase

    deliver_error! 409, message: "Invalid key_id" if data["vendor_specific"]["key_id"] != GitHub.driftwood_stream_key_id

    begin
      stream = update_vendor_specific_fields(stream, data)
      deliver_error 400 if stream.nil?

      stream_hash = bundle_audit_log_stream(stream)

      deliver_raw(stream_hash, status: 200)
    rescue SinkError => e
      deliver_error 400, message: e.message
    rescue ActiveRecord::RecordInvalid => e
      deliver_error 422, message: e.message
    end
  end

  post "/enterprises/:enterprise_id/audit-log/streams", operation_id: "enterprise-admin/create-audit-log-stream" do
    enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.flipper[:audit_log_streaming_conf_api].enabled?(enterprise)

    control_access :create_audit_log_stream,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      resource: enterprise

    data = receive_with_openapi

    deliver_error! 409 if data["vendor_specific"]["key_id"] != GitHub.driftwood_stream_key_id

    begin
      stream_type = data["stream_type"]
      vendor_specific_data = data["vendor_specific"]

      config = STREAM_TYPE_MAPPING[stream_type]
      raise StandardError, "Unsupported stream type" unless config

      permitted_data = vendor_specific_data.deep_symbolize_keys.slice(*config[:permitted_params])

      sink = config[:model].new(permitted_data)
      stream = ::AuditLogStreamConfiguration.new(sink: sink)
      sink_result = stream.check_sink(enterprise, sink)

      raise SinkError, "Endpoint Check Failed: #{sink_result}" unless sink_result == "ok"

      stream = enterprise.audit_log_stream_configurations.build(sink: sink, enabled: data["enabled"])

      if stream.save
        stream_hash = bundle_audit_log_stream(stream)
        deliver_raw(stream_hash, status: 200)
      else
        deliver_error 422, message: stream.errors.full_messages.to_sentence
      end

    rescue SinkError => e
      deliver_error 400, message: e.message
    rescue ActiveRecord::RecordInvalid => e
      deliver_error 422, message: e.message
    end
  end

  def update_vendor_specific_fields(stream, data)
    stream_type = data["stream_type"]
    vendor_specific_data = data["vendor_specific"]
    enabled = data["enabled"]
    paused = Time.now if !enabled

    config = STREAM_TYPE_MAPPING[stream_type]
    raise SinkError, "Unsupported stream type" unless config

    sink = stream.sink
    raise SinkError, "Unsupported sink type" unless sink.is_a?(config[:model])

    permitted_data = vendor_specific_data.deep_symbolize_keys.slice(*config[:permitted_params])

    sink = config[:model].new(permitted_data)
    test_stream = ::AuditLogStreamConfiguration.new(sink: sink)
    sink_result = test_stream.check_sink(stream.business, sink)

    raise SinkError, "Endpoint Check Failed: #{sink_result}" unless sink_result == "ok"

    stream.update!(
      enabled: enabled,
      paused_at: paused,
      updated_at: Time.now,
      sink: sink,
    )
    stream
  end

  def bundle_audit_log_stream(stream)
    stream.as_json
  end

  def rate_limit_configuration
    return unless current_user&.feature_enabled?(:audit_log_api_rate_limit)
    return if current_user&.feature_enabled?(:audit_log_rate_limit_exempt)
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::AUDIT_LOG_STREAMING_FAMILY,
      self,
    )
  end
end
