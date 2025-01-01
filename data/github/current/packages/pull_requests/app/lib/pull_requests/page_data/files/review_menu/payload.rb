# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::ReviewMenu
  class Payload
    class DiffLine < T::Struct
      const :html, String
      const :left, T.nilable(Numeric)
      const :right, T.nilable(Numeric)
      const :text, String
      const :type, String
    end

    class ThreadSubject < T::Struct
      const :diffLines, T.nilable(T::Array[DiffLine])
      const :endLine, T.nilable(Numeric)
      const :endDiffSide, T.nilable(PullRequests::PageData::Files::ReviewMenu::Loader::DiffSide)
      const :originalEndLine, T.nilable(Numeric)
      const :originalStartLine, T.nilable(Numeric)
      const :pullRequestCommit, T.nilable(String)
      const :startDiffSide, T.nilable(PullRequests::PageData::Files::ReviewMenu::Loader::DiffSide)
      const :startLine, T.nilable(Numeric)
    end

    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    class CommentAuthor < T::Struct
      const :author, T.nilable(Author)
    end

    class CommentPreview < T::Struct
      const :bodyHTML, String
      const :threadId, String
      const :commentId, String
      const :isOutdated, T::Boolean
      const :isResolved, T::Boolean
      const :line, T.nilable(Numeric)
      const :path, String
      const :subject, ThreadSubject
      const :subjectType, String
      const :threadPreviewComments, T::Array[CommentAuthor]
    end

    class PendingReview < T::Struct
      # This is nil when there is no pending review for the user
      const :id, T.nilable(Numeric)
      const :comments, T::Array[CommentPreview]
    end

    sig do
      params(
        pending_review: PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview
      ).returns(PendingReview)
    end
    def self.call(pending_review)
      new.call(pending_review)
    end

    sig do
      params(
        pending_review: PullRequests::PageData::Files::ReviewMenu::Loader::PendingReview
      ).returns(PendingReview)
    end
    def call(pending_review)
      PendingReview.new(
        id: pending_review.review&.id,
        comments: pending_review.review_comments.map do |comment|
          CommentPreview.new(
            bodyHTML: comment.body_html,
            threadId: comment.thread_id,
            commentId: comment.comment_id,
            isOutdated: comment.is_outdated,
            isResolved: comment.is_resolved,
            line: comment.line,
            path: comment.path,
            subject: ThreadSubject.new(
              diffLines: comment.subject.diff_lines&.map do |diff_line|
                DiffLine.new(
                  html: diff_line[:html],
                  left: diff_line[:left],
                  right: diff_line[:right],
                  text: diff_line[:text],
                  type: diff_line[:type].to_s.upcase
                )
              end,
              endLine: comment.subject.end_line,
              endDiffSide: comment.subject.end_diff_side,
              originalEndLine: comment.subject.original_end_line,
              originalStartLine: comment.subject.original_start_line,
              pullRequestCommit: comment.subject.pull_request_commit,
              startDiffSide: comment.subject.start_diff_side,
              startLine: comment.subject.start_line
            ),
            subjectType: comment.subject_type,
            # We do not want the last comment in the thread since that is the comment we are previewing.
            # This list is used to build the previews of the other comments in the thread.
            threadPreviewComments: comment.thread_comments.first(comment.thread_comments.size - 1).map do |comment|
              author = comment.user
              if author.present?
                author_payload = Author.new(
                  login: author.display_login,
                  avatarUrl: author.primary_avatar_url
                )
              end

              CommentAuthor.new(
                author: author_payload
              )
            end
          )
        end
      )
    end
  end
end
