# typed: true
# frozen_string_literal: true

class AuditLogSplunkSinkConfiguration < AuditLogSinkConfiguration

  SINK_TYPE = "Splunk".freeze
  STREAMING_API_KEY = "splunks".freeze

  validates_length_of :domain, maximum: 1024
  validates_length_of :encrypted_token, maximum: 1024

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_domain?
      updated_attrs_audit[:new_splunk_domain] = domain
      updated_attrs_audit[:old_splunk_domain] = domain_before_last_save if domain_before_last_save
    end

    if saved_change_to_port?
      updated_attrs_audit[:new_splunk_port] = port
      updated_attrs_audit[:old_splunk_port] = port_before_last_save if port_before_last_save
    end

    updated_attrs_audit[:ssl_verify] = ssl_verify? if saved_change_to_ssl_verify?

    secrets_updated = []
    updated_attrs_audit[:secrets_updated] = ["Token"] if saved_change_to_encrypted_token?

    business = T.must(audit_log_stream_configuration).business
    {
      audit_log_stream_sink: :splunk,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    client.stream_splunk_check(
      subject_id: business.id,
      domain: domain,
      port: port,
      key_id: key_id,
      encrypted_token: encrypted_token,
      ssl_verify: ssl_verify?)
  end

  def sink_url_method(business = nil)
    unless business.audit_log_multiple_streaming_endpoint_enabled?
      return :settings_audit_log_splunk_sink_enterprise_path
    end
    :settings_audit_log_splunk_sinks_show_enterprise_path
  end

  def sink_type
    SINK_TYPE
  end

  def sink_details
    "#{domain}:#{port}"
  end

  def as_streaming_api_conf
    {
      domain: domain,
      port: port,
      encrypted_token: encrypted_token,
      ssl_verify: ssl_verify?,
    }
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def get_input
    domain
  end
end
