# typed: true
# frozen_string_literal: true

class Issues::CopilotSummarizeBannerStaffbarComponent < ApplicationComponent

  sig { params(controller_name: String, action_name: String).void }
  def initialize(controller_name:, action_name:)
    @controller_name = controller_name
    @action_name = action_name
  end

  def call
    render(Copilot::SummarizeBannerStaffbarComponent.new(
      icon: :"issue-opened",
      default_prompt: Issue::CopilotSummarizer::USER_PROMPT,
      test_selector: "copilot-issue-summary-controls-modal",
    ))
  end

  private

  sig { returns T::Boolean }
  def render?
    relevant_page? && Issue::CopilotSummarizer.feature_enabled?(viewer: current_user)
  end

  sig { returns T::Boolean }
  def relevant_page?
    @controller_name == "issues" && @action_name == "show" ||
    @controller_name == "issues_fragments" && @action_name == "issue_layout"
  end
end
