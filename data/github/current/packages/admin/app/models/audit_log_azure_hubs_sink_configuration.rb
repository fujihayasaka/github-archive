
# typed: true
# frozen_string_literal: true

class AuditLogAzureHubsSinkConfiguration < AuditLogSinkConfiguration

  SINK_PATH = "azure-hubs".freeze
  SINK_TYPE = "Azure Event Hubs".freeze
  STREAMING_API_KEY = "azure_hubs".freeze

  validates_length_of :name, maximum: 1024
  validates_length_of :encrypted_connstring, maximum: 1024

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_name?
      updated_attrs_audit[:new_event_hub_instance] = name
      updated_attrs_audit[:old_event_hub_instance] = name_before_last_save if name_before_last_save
    end

    updated_attrs_audit[:secrets_updated] = ["Connection String"] if saved_change_to_encrypted_connstring?

    business = T.must(audit_log_stream_configuration).business
    stream_id = T.must(audit_log_stream_configuration).id
    {
      audit_log_stream_sink: sink_type,
      audit_log_stream_id: stream_id,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    client.stream_azure_hubs_check(
      subject_id: business.id,
      name: name,
      key_id: key_id,
      encrypted_connstring: encrypted_connstring,
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
    name
  end

  def as_streaming_api_conf
    {
      name: name,
      encrypted_connstring: encrypted_connstring,
    }
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def get_input
    name
  end
end
