# typed: true
# frozen_string_literal: true

module Discussions
  class CopilotSummarizeBannerComponent < ApplicationComponent
    STAFF_FEEDBACK_DISCUSSION_URL = "https://gh.io/discussion-summary-feedback"
    PREVIEW_FEEDBACK_DISCUSSION_URL = "https://gh.io/discussion-summary-feedback-preview"
    DESCRIPTION = "Summarize key takeaways of the discussion"

    sig { params(discussion: Discussion, repository: Repository).void }
    def initialize(discussion:, repository:)
      @discussion = discussion
      @repository = repository
    end

    def call
      render(Copilot::SummarizeBannerComponent.new(
        summary_path: copilot_discussion_summaries_path(repository.owner_display_login, repository, discussion),
        description: DESCRIPTION,
        repository: repository,
        negative_feedback_labels: Discussion::CopilotSummarizer::DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS,
        feedback_path: copilot_discussion_summary_feedback_path(repository.owner_display_login, repository,
          discussion),
        feedback_discussion_url: feedback_discussion_url,
        test_selector: "discussions-copilot-summary",
        websocket_channel: live_update_view_channel(discussion.summary_websocket_channel),
        content_type: :discussion,
        reference_name: "discussion summary",
      ))
    end

    private

    sig { returns T.nilable(T::Boolean) }
    def render?
      Discussion::CopilotSummarizer.can_be_summarized?(discussion: discussion, viewer: current_user,
        copilot_user: current_copilot_user_v2)
    end

    sig { returns String }
    def feedback_discussion_url
      if helpers.staff_viewer?
        STAFF_FEEDBACK_DISCUSSION_URL
      else
        PREVIEW_FEEDBACK_DISCUSSION_URL
      end
    end

    sig { returns Discussion }
    attr_reader :discussion

    sig { returns Repository }
    attr_reader :repository
  end
end
