# typed: true
# frozen_string_literal: true

class Businesses::AuditLogSplunkSinkController < Businesses::AuditLogSinkController

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
    "Splunk"
  end

  # Sink class
  def sink_class
    AuditLogSplunkSinkConfiguration
  end

  # Renders the add page for the sink
  def render_add_page(stream, splunk, check_result = nil)
    render "businesses/audit_log_splunk_sink/add",
      locals: {
        stream: stream,
        splunk: splunk,
        token_placeholder: splunk.encrypted_token.blank? ? "" : "* * * * * *",
        form_route: get_form_route(current_business),
        business: current_business,
        check_result: check_result,
        check_is_ok: check_result == "ok",
        public_key: GitHub.driftwood_stream_key,
        public_key_id: GitHub.driftwood_stream_key_id,
      }
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(splunk)
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

  def get_form_route(business)
    stream = business.audit_log_stream_configurations.first

    if stream.nil?
      settings_audit_log_splunk_sink_add_enterprise_path(business)
    else
      settings_audit_log_splunk_sink_update_enterprise_path(business)
    end
  end
end
