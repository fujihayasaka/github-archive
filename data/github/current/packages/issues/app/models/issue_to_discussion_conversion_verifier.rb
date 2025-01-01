# typed: true
# frozen_string_literal: true

# Public: Used to check that an issue to discussion conversion did not fail
class IssueToDiscussionConversionVerifier
  class MissingCommentsError < StandardError; end

  attr_reader :issue, :discussion

  def initialize(issue, discussion)
    @issue = issue
    @discussion = discussion
  end

  def self.verify!(*args)
    T.unsafe(self).new(*args).verify!
  end

  def verify!
    discussion_comment_count = discussion.comments.count
    issue_comment_count = issue.comments.count

    payload = {
      "gh.discussion.id": discussion.id,
      "gh.discussion.number": discussion.number,
      "gh.issue.id": issue.id,
      "gh.issue.number": issue.number,
      "gh.issue.comment_count": issue_comment_count,
      "gh.discussion.comment_count": discussion_comment_count
    }

    GitHub.dogstats.increment "discussion_conversion.attempting_verification"
    GitHub.logger.info(
      "attempting_issue_to_discussion_converstion_verification",
      payload
    )

    if issue_comment_count != discussion_comment_count
      GitHub.dogstats.increment "discussion_conversion.missing_comments"
      GitHub.logger.info(
        "issue_to_discussion_conversion_mismatch",
        payload
      )
      raise MissingCommentsError.new
    end
  end
end
