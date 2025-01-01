# typed: true
# frozen_string_literal: true

module Discussions
  class CopilotSummarizeBannerComponent < ApplicationComponent
    extend T::Sig

    FEEDBACK_DISCUSSION_URL = "https://github.com/github/copilot-core-productivity/discussions/2278"

    sig { params(discussion: Discussion, repository: Repository).void }
    def initialize(discussion:, repository:)
      @discussion = discussion
      @repository = repository
    end

    def call
      render(Copilot::SummarizeBannerComponent.new(
        summary_path: copilot_discussion_summaries_path(repository.owner_display_login, repository, discussion),
        description: "Summarize key takeaways of the discussion",
        repository: repository,
        negative_feedback_labels: Discussion::CopilotSummarizer::DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS,
        feedback_path: copilot_discussion_summary_feedback_path(repository.owner_display_login, repository,
          discussion),
        feedback_discussion_url: FEEDBACK_DISCUSSION_URL,
        test_selector: "discussions-copilot-summary",
        websocket_channel: live_update_view_channel(discussion.summary_websocket_channel),
        content_type: :discussion,
      ))
    end

    private

    sig { returns T.nilable(T::Boolean) }
    def render?
      logged_in? && current_user.copilot_discussion_summary_feature_enabled?
    end

    sig { returns Discussion }
    attr_reader :discussion

    sig { returns Repository }
    attr_reader :repository
  end
end
