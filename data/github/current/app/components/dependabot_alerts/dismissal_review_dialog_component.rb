# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class DismissalReviewDialogComponent < ApplicationComponent
    attr_reader :timeline_event, :dismissal_request_review_path, :alert

    def initialize(timeline_event:, dismissal_request_review_path:, alert:)
      @timeline_event = timeline_event
      @dismissal_request_review_path = dismissal_request_review_path
      @alert = alert
    end
  end
  # rubocop:enable ViewComponent/ComponentsHaveUnitTests
end
