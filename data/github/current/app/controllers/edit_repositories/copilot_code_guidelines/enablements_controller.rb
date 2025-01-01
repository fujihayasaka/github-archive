# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelines::EnablementsController < EditRepositories::AbstractCopilotCodeGuidelinesController
  def create
    respond_to do |format|
      format.turbo_stream do
        # The Primer::SwitchComponent sends a `value` param of either `0` or `1`: https://primer.style/components/toggle-switch/rails/alpha
        guideline.update(enabled: params[:value] == "1")

        render "edit_repositories/copilot_code_guidelines/enablements/create", locals: {
          guidelines: guidelines.limit(Copilot::CodingGuideline::MAX_PER_REPO),
          enabled_count: enabled_count,
        }, layout: false
      end
    end
  end
end
