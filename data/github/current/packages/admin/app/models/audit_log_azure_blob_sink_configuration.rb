# typed: true
# frozen_string_literal: true

class AuditLogAzureBlobSinkConfiguration < AuditLogSinkConfiguration
  SINK_TYPE = "Azure Blob Storage".freeze
  STREAMING_API_KEY = "azure_blobs".freeze

  validates_length_of :container, maximum: 1024
  validates_length_of :encrypted_sas_url, maximum: 1024

  before_validation :set_default_container, on: :create

  def set_default_container
    self.container = "" if self.container.nil?
  end

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_container?
      updated_attrs_audit[:new_azure_blob_container] = container
      updated_attrs_audit[:old_azure_blob_container] = container_before_last_save if container_before_last_save
    end

    updated_attrs_audit[:secrets_updated] = ["Blob SAS Url"] if saved_change_to_encrypted_sas_url?

    business = T.must(audit_log_stream_configuration).business
    {
      audit_log_stream_sink: :azure_blob,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    client.stream_azure_blob_check(
      subject_id: business.id,
      key_id: key_id,
      encrypted_sas_url: encrypted_sas_url,
    )
  end

  def sink_url_method(business = nil)
    unless business.audit_log_multiple_streaming_endpoint_enabled?
      return :settings_audit_log_azure_blob_sink_enterprise_path
    end
    :settings_audit_log_azure_blob_sinks_show_enterprise_path
  end

  def sink_type
    SINK_TYPE
  end

  def sink_details
    container
  end

  def as_streaming_api_conf
    {
      encrypted_sas_url: encrypted_sas_url,
    }
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def get_input
    container
  end
end
