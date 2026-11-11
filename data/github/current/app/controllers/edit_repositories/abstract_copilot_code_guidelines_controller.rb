# typed: true
# frozen_string_literal: true

class EditRepositories::AbstractCopilotCodeGuidelinesController < AbstractRepositoryController
  before_action :ensure_admin_access

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

  sig { returns(T::Boolean) }
  def feature_disabled?
    ff = :copilot_code_review_deprecate_coding_guidelines_playground
    current_user.feature_flag_enabled?(ff, default: false) ||
      current_repository.feature_flag_enabled?(ff, default: false)
  end

  def coding_guideline_feature_enabled?
    ::Copilot::User.new(current_user).copilot_coding_guidelines_enabled?(current_repository)
  end

  sig { void }
  def require_code_guideline_feature_enabled
    render_404 unless coding_guideline_feature_enabled?
  end
end
