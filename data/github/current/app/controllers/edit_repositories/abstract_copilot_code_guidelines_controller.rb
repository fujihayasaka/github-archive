# typed: true
# frozen_string_literal: true

class EditRepositories::AbstractCopilotCodeGuidelinesController < AbstractRepositoryController
  before_action :require_can_change_copilot_enterprise_settings

  private

  sig { returns(Copilot::CodingGuideline) }
  memoize def guideline
    Copilot::CodingGuideline
      .where(repository: current_repository)
      .find(copilot_guideline_id)
  end

  def guidelines
    Copilot::CodingGuideline.where(repository: current_repository).order(:id)
  end

  sig { returns(Integer) }
  memoize def total_count
    guidelines.count
  end

  sig { returns(Integer) }
  memoize def enabled_count
    guidelines.where(enabled: true).count
  end

  # This can be overridden in subclasses to return a different param
  def copilot_guideline_id
    params[:copilot_code_guideline_id]
  end

  sig { void }
  def require_can_change_copilot_enterprise_settings
    render_404 unless ::Copilot::User.new(current_user).copilot_coding_guidelines_enabled?(current_repository)
  end
end
