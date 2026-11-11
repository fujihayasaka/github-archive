# typed: strict
# frozen_string_literal: true

class Orgs::CopilotInsights::ExportController < Orgs::CopilotInsights::Controller
  include Copilot::Organizations::InsightsExport

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations, ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    page_type = params[:page_type]

    case page_type
    when "usage"
      handle_usage_export
    when "code_generation"
      handle_usage_export
    when "impact"
      handle_usage_export
    else
      render json: { error: "Invalid page_type parameter" }, status: :bad_request
    end
  end

  private

  sig { void }
  def handle_usage_export
    begin
      export_files = generate_export_files(this_organization)
      render json: { export_files: export_files }
    rescue => e
      Failbot.report(e)
      render json: { error: "Unable to fetch export files" }, status: :internal_server_error
    end
  end
end
