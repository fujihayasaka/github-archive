# typed: true
# frozen_string_literal: true

class Discussions::CopilotSummarizeBannerStaffbarComponent < ApplicationComponent
  extend T::Sig

  sig { params(controller_name: String, action_name: String, discussion: T.nilable(Discussion)).void }
  def initialize(controller_name:, action_name:, discussion: nil)
    @controller_name = controller_name
    @action_name = action_name
    @discussion = discussion
  end

  def call
    render(Copilot::SummarizeBannerStaffbarComponent.new(
      icon: :"comment-discussion",
      default_prompt: Discussion::CopilotSummarizer::USER_PROMPT,
      test_selector: "copilot-discussion-summary-controls-modal",
    ))
  end

  private

  sig { returns T::Boolean }
  def render?
    relevant_page? && logged_in? && current_user.copilot_discussion_summary_feature_enabled?
  end

  sig { returns T::Boolean }
  def relevant_page?
    @controller_name == "discussions" && @action_name == "show" ||
      @controller_name == "voltron_discussions_fragments" && @action_name == "discussion_layout" ||
      @controller_name.include?("discussion") && @discussion.present?
  end
end
