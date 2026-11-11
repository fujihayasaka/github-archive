# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module Payloads
    # AgentMention repesents a comment or reivew on a Pull Request that
    # mentioned the Copilot Agent and resulted in a Session being created
    class AgentMention
      include T::Props::Serializable
      include AvatarHelper

      class AuthorHash < T::Struct
        prop :id, Integer
        prop :global_relay_id, String
        prop :url, String
        prop :display_login, String
        prop :avatar_url, String
      end

      class AgentMentionHash < T::Struct
        include T::Props::Serializable

        AgentMentionType = T.type_alias { T.deprecated_enum(%w[timeline_comment single_comment_review review]) }

        prop :type, AgentMentionType
        prop :id, Integer
        prop :global_relay_id, String
        prop :pull_request_id, Integer
        prop :body, T.nilable(String)
        prop :url, String # URL to the comment on the timline or the review

        prop :created_at, Time
        prop :updated_at, Time

        prop :author, AuthorHash

        # For single_comment_review types, the comment was on a file/line/range
        # and these fields will be present
        prop :path, T.nilable(String)
        prop :subject_type, T.nilable(String) # line or file

        # For reivew types, the total count of comments in the review will be present
        prop :child_comments, T.nilable(Integer)
      end

      sig do
        params(
          comment: IssueComment,
          pull_request: PullRequest,
        ).returns(AgentMentionHash)
      end
      def self.from_issue_comment(comment, pull_request)
        url_helpers = Rails.application.routes.url_helpers

        repo = T.must(pull_request.repository)
        user = T.must(comment.user)

        AgentMentionHash.new(
          type: "timeline_comment",
          id: comment.id,
          global_relay_id: comment.global_relay_id,
          pull_request_id: pull_request.id,
          body: comment.body,
          url: url_helpers.show_pull_request_path(
            repo.owner,
            repo,
            pull_request,
            anchor: "issuecomment-#{comment.id}",
          ),
          created_at: comment.created_at,
          updated_at: comment.updated_at,
          author: AuthorHash.new(
            id: user.id,
            global_relay_id: user.global_relay_id,
            url: url_helpers.user_path(user),
            display_login: user.display_login,
            avatar_url: user.primary_avatar_url,
          ),
          path: nil,
          subject_type: nil,
          child_comments: nil,
        )
      end

      sig do
        params(
          review: PullRequestReview,
          pull_request: PullRequest,
        ).returns(AgentMentionHash)
      end
      def self.from_review(review, pull_request)
        url_helpers = Rails.application.routes.url_helpers
        user = T.must(review.user)
        repo = T.must(pull_request.repository)

        review_comments = review.review_comments

        # A single comment review is created by commenting on a file/line/range
        # and leaving a single comment rather than starting a review. These are
        # stored as PullRequestReview records with a single associated
        # PullRequestReviewComment.
        single_comment_review = review.body.to_s.strip.empty? && review_comments.size == 1

        if single_comment_review
          comment = T.must(review_comments.first)
          AgentMentionHash.new(
            type: "single_comment_review",
            id: review.id,
            global_relay_id: review.global_relay_id,
            pull_request_id: pull_request.id,
            body: comment.body, # Use the comment body as the review body will be empty
            url: review.permalink(include_host: false),
            created_at: comment.created_at,
            updated_at: comment.updated_at,
            author: AuthorHash.new(
              id: user.id,
              global_relay_id: user.global_relay_id,
              url: url_helpers.user_path(user),
              display_login: user.display_login,
              avatar_url: user.primary_avatar_url,
            ),
            path: T.unsafe(comment).path,
            subject_type: T.unsafe(comment).subject_type,
            child_comments: nil,
          )
        else
          AgentMentionHash.new(
            type: "review",
            id: review.id,
            global_relay_id: review.global_relay_id,
            pull_request_id: pull_request.id,
            body: review.body,
            url: review.permalink(include_host: false),
            created_at: review.created_at,
            updated_at: review.updated_at,
            author: AuthorHash.new(
              id: user.id,
              global_relay_id: user.global_relay_id,
              url: url_helpers.user_path(user),
              display_login: user.display_login,
              avatar_url: user.primary_avatar_url,
            ),
            path: nil,
            subject_type: nil,
            child_comments: review_comments.size,
          )
        end
      end
    end
  end
end
