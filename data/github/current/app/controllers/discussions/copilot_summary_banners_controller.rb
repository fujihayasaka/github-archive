# typed: true
# frozen_string_literal: true

class Discussions::CopilotSummaryBannersController < Discussions::BaseController
  before_action :login_required
  before_action :require_feature
  before_action :require_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations, only: [:show]

  def show
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    render Discussions::CopilotSummarizeBannerComponent.new(discussion: discussion, repository: current_repository), layout: false
  end

  private

  def require_feature
    super # check that discussions is enabled
    return if performed? # bail out if we've already rendered a response

    render_404 unless current_user&.copilot_discussion_summary_feature_enabled?
  end
end
