# typed: true
# frozen_string_literal: true

class AuditLogDatadogSinkConfiguration < AuditLogSinkConfiguration

  SINK_PATH = "datadog".freeze
  SINK_TYPE = "Datadog".freeze
  STREAMING_API_KEY = "datadogs".freeze

  validates_length_of :encrypted_token, maximum: 1024

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_site?
      updated_attrs_audit[:new_datadog_site] = site
      updated_attrs_audit[:old_datadog_site] = site_before_last_save if site_before_last_save
    end

    updated_attrs_audit[:secrets_updated] = ["Token"] if saved_change_to_encrypted_token?

    business = T.must(audit_log_stream_configuration).business
    stream_id = T.must(audit_log_stream_configuration).id
    {
      audit_log_stream_sink: sink_type,
      audit_log_stream_id: stream_id,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    client.stream_datadog_check(
      subject_id: business.id,
      key_id: key_id,
      encrypted_token: encrypted_token,
      site: site,
    )
  end

  def sink_url_method(business = nil)
    unless business.audit_log_multiple_streaming_endpoint_enabled?
      return :show_add_settings_audit_log_stream_enterprise_path
    end
    :show_add_settings_audit_log_streams_enterprise_path
  end

  def sink_type
    SINK_TYPE
  end

  def sink_path
    SINK_PATH
  end

  def sink_details
    SINK_TYPE
  end

  def as_streaming_api_conf
    {
      site: site,
      encrypted_token: encrypted_token,
    }
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def get_input
    ""
  end
end
