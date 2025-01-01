# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelines::EnablementsController < AbstractRepositoryController
  before_action :require_feature_flag
  before_action :ensure_admin_access
  before_action :require_can_change_copilot_enterprise_settings

  def create
    # The Primer::SwitchComponent sends a `value` param of either `0` or `1`: https://primer.style/components/toggle-switch/rails/alpha
    enabled = params[:value] == "1"

    if guideline.update(enabled:)
      flash[:notice] = "Guideline #{enabled ? "enabled" : "disabled"}."
      redirect_to copilot_code_guidelines_path
    else
      flash[:error] = guideline.errors.full_messages.to_sentence
      redirect_to copilot_code_guidelines_path
    end
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
