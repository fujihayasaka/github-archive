# typed: true
#frozen_string_literal: true

class Businesses::AuditLogCuratorController < Businesses::BusinessController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  AUDITLOG_INDEX_NAME = "audit_log".freeze
  before_action :business_owner_required, :enterprise_required

  # GET /businesses/1/audit_log/curator
  def index
    render "businesses/audit_log_curator/index",
      locals: {
        business: current_business,
        stats: stats,
        curator_enabled: GitHub.audit_log_es_curator_enabled?,
        retention_months: setting_months,
        retention_options: retention_options,
        git_events_enabled: git_events_enabled?,
        git_checkbox_disabled: setting_months.value == "inf",
      }
  end

  # post /businesses/1/audit_log/curator
  def update
    if setting_months.update(value: setting_params)
      flash[:notice] = "Audit Log retention settings updated."
    else
      flash[:error] = "Audit Log retention settings could not be updated."
    end
    if setting_params == "inf"
      git_events.update(value: "false")
    end
    redirect_to action: :index
  end

  def git_update # rubocop:todo GitHub/UseRestfulActions
    if git_events.update(value: git_params)
      flash[:notice] = "Git event settings updated"
    else
      flash[:error] = "Git event settings could not be updated."
    end
    redirect_to action: :index
  end

  def stats # rubocop:todo GitHub/UseRestfulActions
    ret = { "total" => 0 }
    begin
      stats = elastomer_client.get("#{AUDITLOG_INDEX_NAME}/_stats/store")

      if stats.success?
        ret = stats.env.body.dig("indices").map { |k, v| [k, v.dig("total", "store", "size_in_bytes")] }.to_h
        ret["total"] = stats.env.body.dig("_all", "total", "store", "size_in_bytes")
      end
    rescue ElastomerClient::Client::IndexNotFoundError => e
      GitHub.logger.error(e)
    end

    ret
  end

  private

  memoize def elastomer_client
    Elastomer.router.client_for_index(AUDITLOG_INDEX_NAME)
  end

  def setting_params
    params[:retention_months]
  end

  def git_params
    params.fetch(:audit_log_settings, {}).fetch(:git_events, false).to_s
  end

  def setting_months
    AuditLogSettings.retention_months
  end

  def git_events_enabled?
    AuditLogSettings.git_events_enabled? && setting_months.value != "inf"
  end

  def git_events
    AuditLogSettings.git_events
  end

  def retention_options
    ["inf", 3, 6, 9, 12].map do |v|
      if v == "inf"
        ["Infinite retention - no data will be removed", v]
      else
        ["#{v} months - data older than #{v} calendar months will be removed", v]
      end
    end
  end
end
