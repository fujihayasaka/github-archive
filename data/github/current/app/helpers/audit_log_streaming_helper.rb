# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/RailsViewRenderLiteral

module AuditLogStreamingHelper
  extend T::Helpers

  def hec_feature_enabled?(business)
    GitHub.flipper[:audit_log_streaming_hec_option].enabled?(business) && !GitHub.enterprise?
  end

  def sink_url(business, stream, type)
    return stream.sink.sink_url(business, type, stream.id) if business.audit_log_multiple_streaming_endpoint_enabled?
    stream.sink.sink_url(business, type)
  end

  def sink_type(stream)
    stream.sink.sink_type
  end

  def sink_path(stream)
    stream.sink.sink_path
  end

  def sink_details(stream)
    stream.sink.sink_details
  end

  # Sink name to use in the UI messages
  def get_sink_name(type)
    sink_names = {
      AuditLogAzureBlobSinkConfiguration::SINK_PATH => AuditLogAzureBlobSinkConfiguration::SINK_TYPE,
      AuditLogAzureHubsSinkConfiguration::SINK_PATH => AuditLogAzureHubsSinkConfiguration::SINK_TYPE,
      AuditLogDatadogSinkConfiguration::SINK_PATH => AuditLogDatadogSinkConfiguration::SINK_TYPE,
      AuditLogGoogleCloudSinkConfiguration::SINK_PATH => AuditLogGoogleCloudSinkConfiguration::SINK_TYPE,
      AuditLogHecSinkConfiguration::SINK_PATH => AuditLogHecSinkConfiguration::SINK_TYPE,
      AuditLogS3SinkConfiguration::SINK_PATH => AuditLogS3SinkConfiguration::SINK_TYPE,
      AuditLogSplunkSinkConfiguration::SINK_PATH => AuditLogSplunkSinkConfiguration::SINK_TYPE
    }
    sink_names[type] || ""
  end

  # Sink class
  def get_sink_class(type)
    sink_names = {
      AuditLogAzureBlobSinkConfiguration::SINK_PATH => AuditLogAzureBlobSinkConfiguration,
      AuditLogAzureHubsSinkConfiguration::SINK_PATH => AuditLogAzureHubsSinkConfiguration,
      AuditLogDatadogSinkConfiguration::SINK_PATH => AuditLogDatadogSinkConfiguration,
      AuditLogGoogleCloudSinkConfiguration::SINK_PATH => AuditLogGoogleCloudSinkConfiguration,
      AuditLogHecSinkConfiguration::SINK_PATH => AuditLogHecSinkConfiguration,
      AuditLogS3SinkConfiguration::SINK_PATH => AuditLogS3SinkConfiguration,
      AuditLogSplunkSinkConfiguration::SINK_PATH => AuditLogSplunkSinkConfiguration
    }
    sink_names[type] || nil
  end

  # Set the given sink attributes using user-provided params
  def get_and_set_sink(params, sink)
    case params[:type]
    when AuditLogAzureBlobSinkConfiguration::SINK_PATH
      set_blob_sink(params, sink)
    when AuditLogAzureHubsSinkConfiguration::SINK_PATH
      set_hubs_sink(params, sink)
    when AuditLogDatadogSinkConfiguration::SINK_PATH
      set_ddog_sink(params, sink)
    when AuditLogGoogleCloudSinkConfiguration::SINK_PATH
      set_gc_sink(params, sink)
    when AuditLogHecSinkConfiguration::SINK_PATH
      set_hec_sink(params, sink)
    when AuditLogS3SinkConfiguration::SINK_PATH
      set_s3_sink(params, sink)
    when AuditLogSplunkSinkConfiguration::SINK_PATH
      set_splunk_sink(params, sink)
    else
      {}
    end
  end

  def base_locals(stream, type, current_business, check_result = nil)
    {
      stream: stream,
      form_route: get_form_route(type, current_business, stream),
      business: current_business,
      check_result: check_result,
      check_is_ok: check_result == "ok",
      public_key: GitHub.driftwood_stream_key,
      public_key_id: GitHub.driftwood_stream_key_id,
    }
  end

  def sink_locals(type, stream, sink, current_business, check_result = nil)
    locals =
      case type
      when AuditLogAzureBlobSinkConfiguration::SINK_PATH
        blob_locals(sink)
      when AuditLogAzureHubsSinkConfiguration::SINK_PATH
        hubs_locals(sink)
      when AuditLogDatadogSinkConfiguration::SINK_PATH
        ddog_locals(sink)
      when AuditLogGoogleCloudSinkConfiguration::SINK_PATH
        gc_locals(sink)
      when AuditLogHecSinkConfiguration::SINK_PATH
        hec_locals(sink)
      when AuditLogS3SinkConfiguration::SINK_PATH
        s3_locals(sink)
      when AuditLogSplunkSinkConfiguration::SINK_PATH
        splunk_locals(sink)
      else
        {}
      end

    locals.merge(base_locals(stream, type, current_business, check_result))
  end

  def get_form_route(type, business, stream)
    return get_form_route_multiple_streams(type, business, stream) if business.audit_log_multiple_streaming_endpoint_enabled?

    get_form_route_single_stream(type, business, stream)
  end

  def get_form_route_single_stream(type, business, stream)
    return UrlHelpers.add_settings_audit_log_stream_enterprise_path(business, type) if stream.nil?

    return UrlHelpers.add_settings_audit_log_stream_enterprise_path(business, type) if !stream.persisted?

    UrlHelpers.update_settings_audit_log_stream_enterprise_path(business, type)
  end

  def get_form_route_multiple_streams(type, business, stream)
    return UrlHelpers.add_settings_audit_log_streams_enterprise_path(business, type) if stream.nil?

    return UrlHelpers.add_settings_audit_log_streams_enterprise_path(business, type) if !stream.persisted?

    UrlHelpers.update_settings_audit_log_streams_enterprise_path(business, type, stream.id)
  end

  # sink locals
  def splunk_locals(sink)
    {
      splunk: sink,
      token_placeholder: sink.encrypted_token.blank? ? "" : "* * * * * *",
    }
  end

  def s3_locals(sink)
    {
      s3: sink,
      access_placeholder: sink.encrypted_access_key_id.blank? ? "" : "* * * * * *",
      secret_placeholder: sink.encrypted_secret_key.blank? ? "" : "* * * * * *",
      authentication_type: sink.authentication_type.nil? ? "access_keys" : sink.authentication_type,
    }
  end

  def gc_locals(sink)
    {
      google_cloud: sink,
      json_placeholder: sink.encrypted_json_credentials.blank? ? "" : "* * * * * *",
    }
  end

  def hec_locals(sink)
    {
      hec: sink,
      token_placeholder: sink.encrypted_token.blank? ? "" : "* * * * * *",
    }
  end

  def blob_locals(sink)
    {
      blob: sink,
      sas_url_placeholder: sink.encrypted_sas_url.blank? ? "" : "* * * * * *",
    }
  end

  def ddog_locals(sink)
    {
      datadog: sink,
      token_placeholder: sink.encrypted_token.blank? ? "" : "* * * * * *",
    }
  end

  def hubs_locals(sink)
    {
      hubs: sink,
      connstring_placeholder: sink.encrypted_connstring.blank? ? "" : "* * * * * *",
    }
  end

  # sink setters
  def set_splunk_sink(params, splunk)
    splunk.domain = params.require(:domain)
    splunk.port = params.require(:port)
    splunk.ssl_verify = params[:ssl_verify] == "on"
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      splunk.encrypted_token = encrypted_value
      splunk.key_id = params.require(:public_key_id)
    end
    splunk
  end

  def set_s3_sink(params, s3)
    s3.bucket = params.require(:s3_bucket)
    s3.authentication_type = params.require(:authentication_type)
    s3.region = params[:s3_region].presence

    case s3.authentication_type
    when s3.oidc_auditlog
      if !GitHub.enterprise?
        s3.arn_role = params.require(:arn_role)

        s3.encrypted_access_key_id = nil
        s3.encrypted_secret_key = nil
        s3.key_id = nil
        s3
      else
        Kernel.raise ArgumentError, "Unexpected authentication type: #{s3.authentication_type}"
      end
    when s3.access_keys
      encrypted_access_key_id_value = params[:key_id_secret_encrypted_value]
      encrypted_secret_key_value = params[:key_secret_encrypted_value]

      if encrypted_access_key_id_value.length > 0 && encrypted_secret_key_value.length > 0
        s3.encrypted_access_key_id = encrypted_access_key_id_value
        s3.encrypted_secret_key = encrypted_secret_key_value
        s3.key_id = params.require(:public_key_id)
      end

      s3.arn_role = nil
      s3
    else
      Kernel.raise ArgumentError, "Unexpected authentication type: #{s3.authentication_type}"
    end
  end

  def set_gc_sink(params, google_cloud)
    google_cloud.bucket = params.require(:gcs_bucket)
    encrypted_json_credentials_value = params[:secret_encrypted_value]

    if encrypted_json_credentials_value.length > 0
      google_cloud.encrypted_json_credentials = encrypted_json_credentials_value
      google_cloud.key_id = params.require(:public_key_id)
    end

    google_cloud
  end

  def set_hec_sink(params, hec)
    hec.domain = params.require(:domain)
    hec.port = params.require(:port)
    hec.path = params[:path].presence || "/"
    hec.ssl_verify = params[:ssl_verify] == "on"
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      hec.encrypted_token = encrypted_value
      hec.key_id = params.require(:public_key_id)
    end
    hec
  end

  def set_blob_sink(params, blob)
    blob.container = params.require(:container)
    encrypted_sas_url = params[:blob_sas_url_secret_encrypted_value]

    if encrypted_sas_url.length > 0
      blob.encrypted_sas_url = encrypted_sas_url
      blob.key_id = params.require(:public_key_id)
    end

    blob
  end

  def set_hubs_sink(params, hubs)
    hubs.name = params.require(:name)
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      hubs.encrypted_connstring = encrypted_value
      hubs.key_id = params.require(:public_key_id)
    end

    hubs
  end

  def set_ddog_sink(params, datadog)
    datadog.site = params.require(:site)
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      datadog.encrypted_token = encrypted_value
      datadog.key_id = params.require(:public_key_id)
    end

    datadog
  end
end
