# typed: true
# frozen_string_literal: true

module GitHub
  module Email
    class Token
      class Error < RuntimeError; end
      class UnknownTargetToken < Error; end
      class LegacyTokenError < Error; end

      LEGACY_TOKEN_REGEX = /\A[[:alpha:]]-[\d]+-[\h]{40}-[\d]+\z/
      TOKEN_SCOPE = "EmailReply"
      TARGET_MAP = {
        "i" => Issue,
        "y" => Milestone,
        "c" => CommitComment,
        "z" => CommitMention,
        "p" => PullRequestReviewComment,
        "g" => Gist,
        "d" => DiscussionPost,
        "a" => RepositoryAdvisory,
        "e" => Discussion,
      }

      # Takes a token and returns a SignedAuthToken instance.
      #
      # token - String token.
      #
      # Returns a SignedAuthToken instance.
      def self.signed_auth_token_from_token(token)
        raise LegacyTokenError if token =~ LEGACY_TOKEN_REGEX
        return nil unless GitHub::Authentication::SignedAuthToken.valid_format?(token)
        GitHub::Authentication::SignedAuthToken.verify(
          token: token,
          scope: TOKEN_SCOPE,
        )
      end

      # Takes a SignedAuthToken and returns a valid Sender.
      # This lets people reply to their notifications from alternate email
      # addresses. However, it only works for new notifications sent since
      # this method was added.
      #
      # signed_auth_token - SignedAuthToken instance.
      #
      # Returns a User instance if the token has a valid user ID at the end.
      def self.sender_from_signed_auth_token(signed_auth_token)
        return unless signed_auth_token.present?
        signed_auth_token.valid? ? signed_auth_token.user : nil
      end

      # Takes a SignedAuthToken and returns a valid record.
      #
      # signed_auth_token - SignedAuthToken instance.
      # user  - Optional User instance that is replying.
      #
      # Returns an ActiveRecord::Base instance if valid, or nil.
      def self.target_from_signed_auth_token(signed_auth_token, user = nil)
        return unless signed_auth_token.present?
        return unless signed_auth_token.valid?
        return unless user.nil? || user == signed_auth_token.user
        target_type, target_id = signed_auth_token.data
        return unless target_class = GitHub::Email::Token::TARGET_MAP[target_type]
        target_class.find_by_id(target_id.to_i)
      end

      # Takes an email token from #target_token and returns a valid Sender.
      # This lets people reply to their notifications from alternate email
      # addresses. However, it only works for new notifications sent since
      # this method was added.
      #
      # token - String token.
      #
      # Returns a User instance if the token has a valid user ID at the end.
      def self.sender_from_token(token)
        raise LegacyTokenError if token =~ LEGACY_TOKEN_REGEX
        return nil unless GitHub::Authentication::SignedAuthToken.valid_format?(token)

        parsed = GitHub::Authentication::SignedAuthToken.verify(
          token: token,
          scope: TOKEN_SCOPE,
        )
        parsed.valid? ? parsed.user : nil
      end

      # Takes an email token from #target_token and returns a valid record.
      #
      # token - String token.
      # user  - Optional User instance that is replying.
      #
      # Returns an ActiveRecord::Base instance if valid, or nil.
      def self.target_from_token(token, user = nil)
        raise LegacyTokenError if token =~ LEGACY_TOKEN_REGEX
        return nil unless GitHub::Authentication::SignedAuthToken.valid_format?(token)

        parsed = GitHub::Authentication::SignedAuthToken.verify(
          token: token,
          scope: TOKEN_SCOPE,
        )

        return unless parsed.valid?
        return unless user.nil? || user == parsed.user
        target_type, target_id = parsed.data
        return unless target_class = GitHub::Email::Token::TARGET_MAP[target_type]
        target_class.find_by_id(target_id.to_i)
      end

      # Creates an email token for the given target.  This token is used in
      # the suffix of reply@github.com email addresses: reply+token@github.com
      #
      # target - ActiveRecord::Base instance.  It should have an associated
      #          mapping in TARGET_MAP.
      # user   - User instance that is replying.
      #
      # Returns a String token.
      def self.target_token(target, user)
        user.signed_auth_token(
          scope: TOKEN_SCOPE,
          expires: 50.years.from_now,
          data: target_to_identifier(target),
        )
      end

      # Private: Get an identifier for a given target. This is a one
      # character String signifying the type of target and the id of the target.
      #
      # target - ActiveRecord::Base instance.  It should have an associated
      #          mapping in TARGET_MAP.
      #
      # Returns an Array. Raises UnknownTargetToken for bad target types.
      def self.target_to_identifier(target)
        case target
        when Issue, CommitComment, PullRequestReviewComment, Gist, DiscussionPost
          [T.must(target.class.name)[0..0]&.downcase, target.id]
        when Milestone
          ["y", target.id]
        when PullRequest, IssueComment
          ["i", target.issue&.id]
        when PullRequestReview
          ["i", target.pull_request&.issue&.id]
        when GistComment
          ["g", target.gist&.id]
        when CommitMention
          ["z", target.id]
        when IssueEventNotification
          ["i", target.issue.id]
        when PullRequestPushNotification
          ["i", target.issue.id]
        when DiscussionPostReply
          ["d", target.discussion_post_id]
        when Discussion
          ["e", target.id]
        when DiscussionComment
          ["e", target.discussion_id]
        when DiscussionEvent::Notification
          ["e", target.discussion.id]
        when RepositoryAdvisory
          ["a", target.id]
        when RepositoryAdvisoryComment, RepositoryAdvisoryEvent
          ["a", target.repository_advisory_id]
        else
          raise UnknownTargetToken, "No target_token for #{target.class.name} id #{target.id}"
        end
      end
    end
  end
end
