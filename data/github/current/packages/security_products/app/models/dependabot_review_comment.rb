# typed: true
# frozen_string_literal: true

class DependabotReviewComment
  attr_accessor :id, :autofix_job_id, :warning_level, :fallback_annotation_title, :fallback_annotation_message, :pull_request_review_comment, :pull_request_number

  def initialize(id:, autofix_job_id:, warning_level:, fallback_annotation_title:, fallback_annotation_message:, pull_request_review_comment:, pull_request_number:)
    @id = id
    @autofix_job_id = autofix_job_id
    @warning_level = warning_level
    @fallback_annotation_title = fallback_annotation_title
    @fallback_annotation_message = fallback_annotation_message
    @pull_request_review_comment = pull_request_review_comment
    @pull_request_number = pull_request_number
  end
end
