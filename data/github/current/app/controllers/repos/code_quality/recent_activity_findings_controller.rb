# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RecentActivityFindingsController < Repos::CodeQuality::BaseRepositoryController
  include CodeQuality::FindingsSerializer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :check_code_quality_read

  sig { void }
  def index
    return render_404 unless CodeQuality.recent_activity_enabled?(current_repository)

    response = GitHub::Turboquality.client.get_ai_findings(Turboquality::Proto::GetAiFindingsRequest.new(
      repository_id: current_repository.id,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    highlighted_diff = SyntaxHighlightedDiff.new(current_repository)

    payload = {
      fileFindings: serialized_ai_file_findings(response.data.ai_file_findings, highlighted_diff),
    }

    render json: payload, status: :ok
  end
end
