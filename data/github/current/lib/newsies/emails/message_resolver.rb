# typed: true
# frozen_string_literal: true
module Newsies
  module Emails
    class MessageResolver
      MessageClasses = [
        Newsies::Emails::AdvisoryCredit,
        Newsies::Emails::CheckSuiteEventNotification,
        Newsies::Emails::CommitComment,
        Newsies::Emails::CommitMention,
        Newsies::Emails::DiscussionPost,
        Newsies::Emails::DiscussionPostReply,
        Newsies::Emails::Discussion,
        Newsies::Emails::DiscussionComment,
        Newsies::Emails::DiscussionEventNotification,
        Newsies::Emails::GistComment,
        Newsies::Emails::Issue,
        Newsies::Emails::IssueComment,
        Newsies::Emails::IssueEventNotification,
        Newsies::Emails::VulnerableRepositoryNotification,
        Newsies::Emails::PullRequest,
        Newsies::Emails::PullRequestComment,
        Newsies::Emails::PullRequestPushNotification,
        Newsies::Emails::PullRequestReview,
        Newsies::Emails::PullRequestReviewComment,
        Newsies::Emails::Release,
        Newsies::Emails::RepositoryAdvisory,
        Newsies::Emails::RepositoryAdvisoryComment,
        Newsies::Emails::RepositoryAdvisoryEvent,
        Newsies::Emails::RepositoryInvitation,
        Newsies::Emails::SecurityAdvisoryNotification,
        Newsies::Emails::WorkflowRunApprovalNotification,
      ]

      # Public: Initialize a message for the given comment.
      #
      # delivery - The delivery with a comment
      # settings - An instance of Newsies::Settings
      #
      # Returns instance of a Newsies::Emails::Message subclass.
      def self.message_for(delivery, settings, options = nil)
        message_class(delivery.comment).new(delivery, settings, options)
      end

      # Public: Determines which Message class to use for the given comment.
      #
      #  comment - An object with a matching Newsies::Emails::* class
      def self.message_class(comment)
        MessageClasses.detect { |c| c.matches?(comment) } ||
          raise(ArgumentError, "No message class defined for #{Newsies::Comment.to_type(comment)}")
      end
    end
  end
end
