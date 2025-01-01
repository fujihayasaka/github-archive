# typed: true
# frozen_string_literal: true

class Issues::CopilotSummarizeBannerComponent < ApplicationComponent
  STAFF_FEEDBACK_DISCUSSION_URL = "https://gh.io/issue-summary-feedback"
  PREVIEW_FEEDBACK_DISCUSSION_URL = "https://gh.io/issue-summary-feedback-preview"
  DESCRIPTION = "Summarize key takeaways of the issue"

  sig { params(issue: Issue, repository: Repository).void }
  def initialize(issue:, repository:)
    @issue = issue
    @repository = repository
  end

  def call
    render(Copilot::SummarizeBannerComponent.new(
      summary_path: copilot_issue_summaries_path(repository.owner_display_login, repository, issue),
      feedback_path: copilot_issue_summary_feedback_path(repository.owner_display_login, repository, issue),
      feedback_discussion_url: feedback_discussion_url,
      description: DESCRIPTION,
      test_selector: "issues-copilot-summary",
      negative_feedback_labels: Issue::CopilotSummarizer::ISSUE_SUMMARY_NEGATIVE_FEEDBACK_LABELS,
      repository: repository,
      websocket_channel: live_update_view_channel(issue.summary_websocket_channel),
      content_type: :issue,
      reference_name: "issue summary",
    ))
  end

  private

  sig { returns T.nilable(T::Boolean) }
  def render?
    Issue::CopilotSummarizer.can_be_summarized?(viewer: current_user, copilot_user: current_copilot_user_v2,
      issue: issue)
  end

  sig { returns String }
  def feedback_discussion_url
    if helpers.staff_viewer?
      STAFF_FEEDBACK_DISCUSSION_URL
    else
      PREVIEW_FEEDBACK_DISCUSSION_URL
    end
  end

  sig { returns Issue }
  attr_reader :issue

  sig { returns Repository }
  attr_reader :repository
end
