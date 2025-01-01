# typed: true
# frozen_string_literal: true

class Issues::CopilotSummaryBannersController < AbstractRepositoryController
  include ControllerMethods::Issues

  before_action :require_feature
  before_action :login_required
  before_action :issue_required
  before_action :require_issues_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations, only: [:show]

  def show
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    render Issues::CopilotSummarizeBannerComponent.new(issue: current_issue, repository: current_repository),
      layout: false
  end

  private

  def require_feature
    render_404 unless feature_enabled_globally_or_for_current_user_or_entity?(:issues_copilot_summary, current_repository.owner)
  end

  def require_issues_enabled
    unless current_issue.pull_request?
      render_404 unless current_repository.has_issues?
    end
  end
end
