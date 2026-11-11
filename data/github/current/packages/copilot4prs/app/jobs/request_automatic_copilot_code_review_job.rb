# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RequestAutomaticCopilotCodeReviewJob < ApplicationJob
  queue_as :request_automatic_copilot_code_review
  retry_on_recoverable_exceptions

  sig { params(pull_request: PullRequest, user: User).void }
  def perform(pull_request, user)
    pull_request.request_automatic_copilot_code_review(user)
  end
end
