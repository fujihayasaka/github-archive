# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Public: Allows bulk conversion of issues to discussions by converting all open issues
# with a specified label.
class ConvertLabelledIssuesToDiscussionsJob < ApplicationJob
  retry_on_dirty_exit
  queue_as :convert_labelled_issues_to_discussions
  locked_by timeout: 1.hour, key: ->(job) { job.build_lock_key }

  # Public: Perform the Issue => Discussion conversion.
  #
  # actor - the current User who initiated the conversion
  # label - a Label to use in filtering open Issues to be converted
  # category - an optional DiscussionCategory to place newly created Discussions
  #
  # Returns nothing.
  def perform(actor, label, category: nil)
    issues = label.issues.open_issues

    if issues.any? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      # TODO: create audit log entry about converting this label's issues into discussions
    end

    issues.each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      convert_issue_to_discussion(issue, actor: actor, category: category)
    end
  end

  def build_lock_key
    label = arguments.second
    "label:#{label.id}"
  end

  private

  def convert_issue_to_discussion(issue, actor:, category:)
    converter = IssueToDiscussionConverter.new(issue, actor: actor, category: category)
    return false unless with_write { converter.prepare_for_conversion }
    with_write { converter.finish_conversion }
  end
end
