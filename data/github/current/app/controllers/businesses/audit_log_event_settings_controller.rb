# typed: true
# frozen_string_literal: true
class Businesses::AuditLogEventSettingsController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :dotcom_required

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
    only: [:show]

  # If business is allowed to see IP disclosure, then show the IP disclosure
  # else redirect to audit log
  def show
    if current_business.show_optional_audit_log_event_settings?
      render "businesses/audit_log/event_settings", locals:
        { business: current_business }
    else
      redirect_to settings_audit_log_enterprise_path(current_business.slug)
    end
  end

  def update
    business = params[:business]
    if business
      if business[:source_ip_disclosure_enabled] == "on"
        current_business.enable_source_ip_disclosure(actor: current_user)
        notice = "Audit log source IP disclosure enabled."
      elsif business[:source_ip_disclosure_enabled] == "off"
        current_business.disable_source_ip_disclosure(actor: current_user)
        notice = "Audit log source IP disclosure disabled."
      end

      if business[:audit_log_code_search_events_enabled] == "on"
        current_business.enable_audit_log_code_search_events(actor: current_user)
        notice = "Audit Log Code Search enabled."
      elsif business[:audit_log_code_search_events_enabled] == "off"
        current_business.disable_audit_log_code_search_events(actor: current_user)
        notice = "Audit Log Code Search disabled."
      end

      if business[:api_request_events_enabled] == "on"
        current_business.enable_api_request_events(actor: current_user)
        notice = "Audit log API request events enabled."
      elsif business[:api_request_events_enabled] == "off"
        current_business.disable_api_request_events(actor: current_user)
        notice = "Audit log API request events disabled."
      end
    end

    redirect_to :back, notice: notice
  end
end
