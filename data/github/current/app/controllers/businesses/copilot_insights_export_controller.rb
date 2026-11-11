# typed: strict
# frozen_string_literal: true

class Businesses::CopilotInsightsExportController < Businesses::CopilotInsightsBaseController
  include Copilot::Businesses::InsightsExport

  skip_before_action :enforce_copilot_insights_allowed

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations, ApplicationRecord::IamAbilities,
    only: [:show]

  before_action :validate_permissions

  sig { void }
  def show
    page_type = params[:page_type]

    case page_type
    when "usage"
      handle_usage_export
    when "code_generation"
      handle_usage_export
    else
      render json: { error: "Invalid page_type parameter" }, status: :bad_request
    end
  end

  private

  sig { void }
  def handle_usage_export
    begin
      export_files = generate_export_files(current_business)
      render json: { export_files: export_files }
    rescue Copilot::Metrics::UsageReport::NoDataAvailableError
      render json: { error: "No data available for export" }, status: :not_found
    rescue => e
      Failbot.report(e)
      render json: { error: "Unable to fetch export files" }, status: :internal_server_error
    end
  end

  sig { void }
  def validate_permissions
    page_type = params[:page_type]

    return unless page_type.present?

    case page_type
    when "usage"
      return if permissions_object.copilot_insights_usage_feature_available?
      render_404
    when "code_generation"
      return if permissions_object.copilot_insights_code_generation_feature_available?
      render_404
    end
  end
end
