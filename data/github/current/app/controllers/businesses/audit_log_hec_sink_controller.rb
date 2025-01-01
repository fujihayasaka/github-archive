# typed: true
# frozen_string_literal: true

class Businesses::AuditLogHecSinkController < Businesses::AuditLogSinkController
  before_action :audit_log_hec_enabled?
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

  def audit_log_hec_enabled?
    return if GitHub.flipper[:audit_log_streaming_hec_option].enabled?(current_business) && !GitHub.enterprise?
    render_404
  end

  # Sink name to use in the UI messages
  def sink_name
    "HTTPS Event Collector"
  end

  # Sink class
  def sink_class
    AuditLogHecSinkConfiguration
  end

  # Renders the add page for the sink
  def render_add_page(stream, hec, check_result = nil)
    render "businesses/audit_log_hec_sink/add",
      locals: {
        stream: stream,
        hec: hec,
        token_placeholder: hec.encrypted_token.blank? ? "" : "* * * * * *",
        form_route: get_form_route(current_business),
        business: current_business,
        check_result: check_result,
        check_is_ok: check_result == "ok",
        public_key: GitHub.driftwood_stream_key,
        public_key_id: GitHub.driftwood_stream_key_id,
      }
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(hec)
    hec.domain = params.require(:domain)
    hec.port = params.require(:port)
    hec.ssl_verify = params[:ssl_verify] == "on"
    encrypted_value = params[:secret_encrypted_value]

    if encrypted_value.length > 0
      hec.encrypted_token = encrypted_value
      hec.key_id = params.require(:public_key_id)
    end
    hec
  end

  def get_form_route(business)
    stream = business.audit_log_stream_configurations.first

    if stream.nil?
      settings_audit_log_hec_sink_add_enterprise_path(business)
    else
      settings_audit_log_hec_sink_update_enterprise_path(business)
    end
  end
end
