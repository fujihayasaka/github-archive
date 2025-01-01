# typed: true
# frozen_string_literal: true

class Businesses::AuditLogS3SinkController < Businesses::AuditLogSinkController

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
    "Amazon S3"
  end

  # Sink class
  def sink_class
    AuditLogS3SinkConfiguration
  end

  # Renders the add page for the sink
  def render_add_page(stream, s3, check_result = nil)
    render "businesses/audit_log_s3_sink/add",
      locals: {
        stream: stream,
        s3: s3,
        business: current_business,
        access_placeholder: s3.encrypted_access_key_id.blank? ? "" : "* * * * * *",
        secret_placeholder: s3.encrypted_secret_key.blank? ? "" : "* * * * * *",
        form_route: get_form_route(current_business),
        check_result: check_result,
        check_is_ok: check_result == "ok",
        public_key: GitHub.driftwood_stream_key,
        public_key_id: GitHub.driftwood_stream_key_id,
        authentication_type: s3.authentication_type.nil? ? "access_keys" : s3.authentication_type,
      }
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(s3)
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
        raise ArgumentError, "Unexpected authentication type: #{s3.authentication_type}"
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
      raise ArgumentError, "Unexpected authentication type: #{s3.authentication_type}"
    end
  end

  def get_form_route(business)
    if business.audit_log_stream_configurations.first.nil?
      settings_audit_log_s3_sink_add_enterprise_path(business)
    else
      settings_audit_log_s3_sink_update_enterprise_path(business)
    end
  end
end
