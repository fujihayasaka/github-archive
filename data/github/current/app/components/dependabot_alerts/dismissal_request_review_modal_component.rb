# typed: true
# frozen_string_literal: true

class DependabotAlerts::DismissalRequestReviewModalComponent < ApplicationComponent
  attr_reader :dismissal_request, :review_path, :alert_number

  def initialize(dismissal_request:, review_path:, alert_number:)
    @dismissal_request = dismissal_request
    @review_path = review_path
    @alert_number = alert_number
  end
end
