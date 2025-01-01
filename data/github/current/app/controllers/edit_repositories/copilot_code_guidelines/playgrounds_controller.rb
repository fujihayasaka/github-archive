# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelines::PlaygroundsController < AbstractRepositoryController
  include ReactHelper

  before_action :require_feature_flag
  before_action :ensure_admin_access
  before_action :require_can_change_copilot_enterprise_settings

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    render "edit_repositories/copilot_code_guidelines/playground/show", locals: {
      coding_guideline: guideline,
    }
  end

  private

  sig { returns(Copilot::CodingGuideline) }
  memoize def guideline
    Copilot::CodingGuideline
      .where(repository: current_repository)
      .find(params[:copilot_code_guideline_id])
  end

  sig { void }
  def require_feature_flag
    render_404 unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
  end

  sig { void }
  def require_can_change_copilot_enterprise_settings
    render_404 unless Copilot::Organization.new(current_repository.owner).can_use_copilot_enterprise_features?
  end
end
