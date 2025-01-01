# typed: true
# frozen_string_literal: true

class Businesses::AuditLogAzureBlobSinksController < Businesses::AuditLogSinksController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show_add]

  private

  # Sink name to use in the UI messages
  def sink_name
    "Azure Blob Storage"
  end

  # Sink class
  def sink_class
    AuditLogAzureBlobSinkConfiguration
  end

  # Renders the add page for the sink
  def render_add_page(stream, sink, check_result = nil)
    sink_id = sink.id
    unless sink_id.present?
      sink_id = params.extract_value(:id)
    end

    render "businesses/audit_log_azure_blob_sink/add",
      locals: {
        stream: stream,
        blob: sink,
        business: current_business,
        sas_url_placeholder: sink.encrypted_sas_url.blank? ? "" : "* * * * * *",
        form_route: get_form_route(current_business, sink_id),
        check_result: check_result,
        check_is_ok: check_result == "ok",
        public_key: GitHub.driftwood_stream_key,
        public_key_id: GitHub.driftwood_stream_key_id,
      }
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(blob)
    blob.container = params.require(:container)
    encrypted_sas_url = params[:blob_sas_url_secret_encrypted_value]

    if encrypted_sas_url.length > 0
      blob.encrypted_sas_url = encrypted_sas_url
      blob.key_id = params.require(:public_key_id)
    end

    blob
  end

  def get_form_route(business, id)
    stream = business.audit_log_stream_configurations.find_by(id: id)

    if stream.nil?
      settings_audit_log_azure_blob_sinks_add_enterprise_path(business)
    else
      settings_audit_log_azure_blob_sinks_update_enterprise_path(business)
    end
  end
end
