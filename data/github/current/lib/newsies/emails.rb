# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    autoload :AdvisoryCredit, "newsies/emails/advisory_credit"
    autoload :CheckSuiteEventNotification, "newsies/emails/check_suite_event_notification"
    autoload :CommitComment, "newsies/emails/commit_comment"
    autoload :CommitMention, "newsies/emails/commit_mention"
    autoload :Discussion, "newsies/emails/discussion"
    autoload :DiscussionComment, "newsies/emails/discussion_comment"
    autoload :DiscussionEventNotification, "newsies/emails/discussion_event_notification"
    autoload :DiscussionPost, "newsies/emails/discussion_post"
    autoload :DiscussionPostReply, "newsies/emails/discussion_post_reply"
    autoload :GateRequest, "newsies/emails/gate_request"
    autoload :GistComment, "newsies/emails/gist_comment"
    autoload :Issue, "newsies/emails/issue"
    autoload :IssueDeliveryCheck, "newsies/emails/issue_delivery_check"
    autoload :IssueComment, "newsies/emails/issue_comment"
    autoload :IssueEventNotification, "newsies/emails/issue_event_notification"
    autoload :Message, "newsies/emails/message"
    autoload :MessageResolver, "newsies/emails/message_resolver"
    autoload :VulnerableRepositoryNotification, "newsies/emails/vulnerable_repository_notification"
    autoload :SecurityAdvisoryNotification, "newsies/emails/security_advisory_notification"
    autoload :PullRequest, "newsies/emails/pull_request"
    autoload :PullRequestComment, "newsies/emails/pull_request_comment"
    autoload :PullRequestPushNotification, "newsies/emails/pull_request_push_notification"
    autoload :PullRequestReview, "newsies/emails/pull_request_review"
    autoload :PullRequestReviewComment, "newsies/emails/pull_request_review_comment"
    autoload :Release, "newsies/emails/release"
    autoload :RepositoryAdvisory, "newsies/emails/repository_advisory"
    autoload :RepositoryAdvisoryComment, "newsies/emails/repository_advisory_comment"
    autoload :RepositoryAdvisoryEvent, "newsies/emails/repository_advisory_event"
    autoload :RepositoryInvitation, "newsies/emails/repository_invitation"
  end
end
