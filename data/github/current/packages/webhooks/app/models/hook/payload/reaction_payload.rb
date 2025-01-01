# typed: true
# frozen_string_literal: true

class Hook::Payload::ReactionPayload < Hook::Payload
  # The payload defined as a Ruby hash. Our event instance is available
  # as `hook_event`.
  #
  # In addition to any keys defined here, The `target_repository`,
  # `target_organization`, and `actor` from the event will be mixed in as
  # `repository`, `organization`, and `sender` respectively.
  def to_payload_hash
    {
      action: hook_event.action,
      content: hook_event.content,
      reaction_id: hook_event.reaction_id,
      subject_id: hook_event.subject_id,
      subject_type: hook_event.subject_type,
      subject_url: subject_url(hook_event.subject_type, hook_event.subject_id),
      subject_html_url: subject_html_url(hook_event.subject_type, hook_event.subject_id),
      reacted_at: Api::Serializer.time(hook_event.reacted_at),
    }
  end

  private

  def subject_url(subject_type, subject_id)
    subject = Reaction.find_subject(subject_id, subject_type)

    case subject.class.name
    when "Discussion"
      api_serialize(:discussion_hash, subject)[:html_url]
    when "DiscussionComment"
      api_serialize(:discussion_comment_hash, subject)[:html_url]
    when "Issue"
      api_serialize(:issue_hash, subject)[:url]
    when "PullRequest"
      api_serialize(:pull_request_hash, subject)[:url]
    when "IssueComment"
      api_serialize(:issue_comment_hash, subject)[:url]
    when "CommitComment"
      api_serialize(:commit_comment_hash, subject)[:url]
    when "PullRequestReview"
      api_serialize(:pull_request_review_hash, subject)[:html_url]
    when "PullRequestReviewComment"
      api_serialize(:pull_request_review_comment_hash, subject)[:url]
    when "Release"
      api_serialize(:release_hash, subject)[:url]
    when "RepositoryAdvisory"
      api_serialize(:repository_advisory_hash, subject)[:url]
    when "RepositoryAdvisoryComment"
      subject.permalink
    end
    # "DiscussionPost", "DiscussionPostReply" are out of scope for Enterprise Live Migrations
    # and don't have a webhook support on it's own right now
  end

  def subject_html_url(subject_type, subject_id)
    subject = Reaction.find_subject(subject_id, subject_type)

    case subject.class.name
    when "Discussion"
      api_serialize(:discussion_hash, subject)[:html_url]
    when "DiscussionComment"
      api_serialize(:discussion_comment_hash, subject)[:html_url]
    when "Issue"
      api_serialize(:issue_hash, subject)[:html_url]
    when "PullRequest"
      api_serialize(:pull_request_hash, subject)[:html_url]
    when "IssueComment"
      api_serialize(:issue_comment_hash, subject)[:html_url]
    when "CommitComment"
      api_serialize(:commit_comment_hash, subject)[:html_url]
    when "PullRequestReview"
      api_serialize(:pull_request_review_hash, subject)[:html_url]
    when "PullRequestReviewComment"
      api_serialize(:pull_request_review_comment_hash, subject)[:html_url]
    when "Release"
      api_serialize(:release_hash, subject)[:html_url]
    when "RepositoryAdvisory"
      api_serialize(:repository_advisory_hash, subject)[:html_url]
    when "RepositoryAdvisoryComment"
      subject.permalink
    end
    # "DiscussionPost", "DiscussionPostReply" are out of scope for Enterprise Live Migrations
    # and don't have a webhook support on it's own right now
  end
end
