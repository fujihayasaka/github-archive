# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelines::EnablementsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  def create
    respond_to do |format|
      format.turbo_stream do
        # The Primer::ToggleSwitch component sends a `value` param of either `0` or `1`: https://primer.style/components/toggle-switch/rails/alpha
        guideline.update(enabled: params[:value] == "1")

        render "edit_repositories/copilot_code_guidelines/enablements/create", locals: {
          autofocus_guideline_id: guideline.id,
          guidelines: guidelines.limit(Copilot::CodingGuideline::MAX_PER_REPO),
          enabled_count: enabled_count,
          feature_is_disabled: feature_disabled?,
        }, layout: false
      end
    end
  end
end
