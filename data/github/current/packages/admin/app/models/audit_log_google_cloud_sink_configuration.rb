# typed: true
# frozen_string_literal: true

class AuditLogGoogleCloudSinkConfiguration < AuditLogSinkConfiguration

  SINK_TYPE = "Google Cloud Storage".freeze
  STREAMING_API_KEY = "gcp_buckets".freeze

  validates_length_of :bucket, maximum: 1024
  validates_length_of :encrypted_json_credentials, maximum: 4096

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_bucket?
      updated_attrs_audit[:new_gc_bucket] = bucket
      updated_attrs_audit[:old_gc_bucket] = bucket_before_last_save if bucket_before_last_save
    end

    updated_attrs_audit[:secrets_updated] = ["JSON Credentials"] if saved_change_to_encrypted_json_credentials?

    business = T.must(audit_log_stream_configuration).business
    {
      audit_log_stream_sink: :google_cloud,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    client.stream_gcp_storage_check(
      subject_id: business.id,
      bucket: bucket,
      key_id: key_id,
      encrypted_json_credentials: encrypted_json_credentials,
    )
  end

  def sink_url_method(business = nil)
    unless business.audit_log_multiple_streaming_endpoint_enabled?
      return :settings_audit_log_google_cloud_sink_enterprise_path
    end
    :settings_audit_log_google_cloud_sinks_show_enterprise_path
  end

  def sink_type
    SINK_TYPE
  end

  def sink_details
    bucket
  end

  def as_streaming_api_conf
    {
       bucket: bucket,
       encrypted_json_credentials: encrypted_json_credentials,
    }
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def get_input
    bucket
  end
end
