# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::IssueComments
  class Payload
    class IssueComment < T::Struct
      const :id, String
      const :authorAssociation, String
      const :authorAvatarUrl, T.nilable(String)
      const :authorLogin, String
      const :body, String
      const :bodyHtml, String
      const :createdAt, String
      const :isHidden, T::Boolean
      const :minimizedReason, T.nilable(String)
      const :reactionGroups, T::Array[PullRequests::PageData::Helpers::Reactable::Payload::ReactionGroup]
      const :repository, T.nilable(PullRequests::PageData::Helpers::Repository::Payload::Repository)
      const :url, String
      const :viewerCanReact, T::Boolean
    end

    sig do
      params(
        issue_comments: T::Array[PullRequests::PageData::IssueComments::Loader::IssueComment]
      ).returns(T::Array[IssueComment])
    end
    def self.call(issue_comments)
      new.call(issue_comments)
    end

    sig do
      params(
        issue_comments: T::Array[PullRequests::PageData::IssueComments::Loader::IssueComment]
      ).returns(T::Array[IssueComment])
    end
    def call(issue_comments)
      issue_comments.map do |issue_comment|
        comment = issue_comment.comment
        repository_payload = PullRequests::PageData::Helpers::Repository::Payload.build_repository(comment.repository)

        IssueComment.new(
          id: issue_comment.id,
          authorAssociation: issue_comment.author_association,
          authorAvatarUrl: issue_comment.author_avatar_url,
          authorLogin: issue_comment.author_login,
          body: comment.body,
          bodyHtml: issue_comment.body_html,
          createdAt: comment.created_at.iso8601,
          isHidden: comment.minimized?,
          minimizedReason: comment.minimized_reason,
          reactionGroups: PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(issue_comment.reaction_groups),
          repository: repository_payload,
          url: issue_comment.url,
          viewerCanReact: issue_comment.viewer_can_react,
        )
      end
    end
  end
end
