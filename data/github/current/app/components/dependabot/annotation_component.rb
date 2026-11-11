# typed: true
# frozen_string_literal: true

class Dependabot::AnnotationComponent < ApplicationComponent
  include ::TextHelper

  renders_one :disclaimer

  attr_reader :autofix_job_id, :inline, :repository, :warning_level, :annotation_title, :annotation_message, :annotation_id, :pull_request_review_thread

  def initialize(inline: false, dependabot_annotation_result: nil, annotation_id: 0, fallback_warning_level:, fallback_annotation_title:, fallback_annotation_message:, autofix_job_id:, repository:, pull_request: nil, pull_request_review_thread: nil)
    @inline = inline
    @dependabot_annotation_result = dependabot_annotation_result
    @annotation_id = annotation_id
    @repository = repository
    @autofix_job_id = autofix_job_id
    @pull_request = pull_request
    @pull_request_review_thread = pull_request_review_thread
    @warning_level = fallback_warning_level.presence || "failure"

    @annotation_title = if @dependabot_annotation_result&.title.present?
      @dependabot_annotation_result&.title
    else
      fallback_annotation_title.presence || "Fix breaking changes caused by dependency update"
    end

    @annotation_message = if @dependabot_annotation_result&.message.present?
      @dependabot_annotation_result.message
    else
      fallback_annotation_message.presence || "Breaking changes caused by dependency update."
    end
  end

  def div_if_inline(**attrs, &block)
    return tag.div(**attrs, &block) if @inline
    capture(&block)
  end
end
