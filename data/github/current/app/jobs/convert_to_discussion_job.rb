# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ConvertToDiscussionJob < ApplicationJob
  queue_as :convert_to_discussion
  retry_on_dirty_exit
  discard_on ActiveJob::DeserializationError
  retry_on IssueToDiscussionConversionVerifier::MissingCommentsError,
    wait: :polynomially_longer,
    attempts: 3

  def perform(actor, discussion, issue_originally_open = nil)
    issue = discussion.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return unless issue

    converter = IssueToDiscussionConverter.new(issue, actor: actor,
      issue_originally_open: issue_originally_open)
    with_write { converter.finish_conversion }
  end
end
