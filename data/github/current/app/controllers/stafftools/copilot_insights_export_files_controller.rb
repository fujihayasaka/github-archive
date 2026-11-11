# typed: true
# frozen_string_literal: true

class Stafftools::CopilotInsightsExportFilesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include ::CopilotInsightsUsage::Stafftools
  include ::Copilot::Organizations::InsightsExport

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :ensure_user_exists
  before_action :ensure_usage_dashboard_entity_supported

  def index
    export_files = generate_export_files(this_user)
    render json: { export_files: export_files }
  rescue => e
    Failbot.report(e)
    render json: { error: "Unable to fetch export files" }, status: :internal_server_error
  end
end
