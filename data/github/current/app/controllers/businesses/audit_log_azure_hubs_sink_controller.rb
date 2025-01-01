# typed: true
# frozen_string_literal: true

class Businesses::AuditLogAzureHubsSinkController < Businesses::AuditLogSinkController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show_add]

  private

  # Sink name to use in the UI messages
  def sink_name
    "Azure Event Hub"
  end

  # Sink class
  def sink_class
    AuditLogAzureHubsSinkConfiguration
  end

  # Renders the add page for the sink
  def render_add_page(stream, hubs, check_result = nil)
    render "businesses/audit_log_azure_hubs_sink/add",
      locals: {
        stream: stream,
        hubs: hubs,
        business: current_business,
        connstring_placeholder: hubs.encrypted_connstring.blank? ? "" : "* * * * * *",
        form_route: get_form_route(current_business),
        check_result: check_result,
        check_is_ok: check_result == "ok",
        public_key: GitHub.driftwood_stream_key,
        public_key_id: GitHub.driftwood_stream_key_id,
      }
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(hubs)
    hubs.name = params.require(:name)
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      hubs.encrypted_connstring = encrypted_value
      hubs.key_id = params.require(:public_key_id)
    end

    hubs
  end

  def get_form_route(business)
    if business.audit_log_stream_configurations.first.nil?
      settings_audit_log_azure_hubs_sink_add_enterprise_path(business)
    else
      settings_audit_log_azure_hubs_sink_update_enterprise_path(business)
    end
  end
end
