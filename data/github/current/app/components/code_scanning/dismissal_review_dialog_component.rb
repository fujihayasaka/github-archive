# typed: true
# frozen_string_literal: true

class CodeScanning::DismissalReviewDialogComponent < ApplicationComponent
  attr_reader :timeline_event, :dismissal_request_review_path

  sig do
    params(
      timeline_event: CodeScanning::AlertTimelineEvent,
      dismissal_request_review_path: String
    ).void
  end
  def initialize(timeline_event:, dismissal_request_review_path:)
    @timeline_event = timeline_event
    @dismissal_request_review_path = dismissal_request_review_path
  end
end
