# frozen_string_literal: true

class ResolveCVERequestJob < ApplicationJob
  queue_as :default

  def perform(cve_request_id)
    cve_request = CVERequest.find(cve_request_id)
    CVEReview.create_or_reopen_from_cve_request!(cve_request)
  end
end
