# typed: true
# frozen_string_literal: true

class Orgs::AuditLogEventSettingsController < Orgs::Controller
  before_action :read_org_audit_logs_permission_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    if this_organization.show_optional_audit_log_event_settings?
      render "orgs/audit_log/event_settings", locals:
        { organization: this_organization }
    else
      redirect_to settings_org_audit_log_path(this_organization)
    end
  end

  def update
    org = params[:organization]
    if org
      if org[:source_ip_disclosure_enabled] == "on"
        this_organization.enable_source_ip_disclosure(actor: current_user)
        notice = "Audit log source IP disclosure enabled."
      elsif org[:source_ip_disclosure_enabled] == "off"
        this_organization.disable_source_ip_disclosure(actor: current_user)
        notice = "Audit log source IP disclosure disabled."
      end
    end
    redirect_to :back, notice: notice
  end
end
