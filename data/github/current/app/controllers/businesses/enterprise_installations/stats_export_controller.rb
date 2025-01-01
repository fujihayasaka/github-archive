# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseInstallations::StatsExportController < Businesses::BusinessController
  before_action :business_owner_required

  def create
    GitHub.dogstats.time "s4.usage_metrics.export.timing" do
      # Download the usage metrics from the S4 service
      export_data = this_business.s4_usage_metrics(format: params[:format])
      GitHub.dogstats.increment("s4.usage_metrics.export",
        tags: ["status:#{export_data == GitHub::Connect::S4::ERROR_METRICS_RESPONSE ? "error" : "success"}"])
      this_business.instrument_connect_usage_metrics_export actor: current_user, total_entries: export_data[:record_count]
      send_data export_data[:blob], type: export_data[:content_type], filename: "stats-export.#{params[:format]}"
    end
  end
end
