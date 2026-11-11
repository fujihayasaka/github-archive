# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Payload
    class DiffLine < T::Struct
      const :html, String
      const :left, T.nilable(Numeric)
      const :right, T.nilable(Numeric)
      const :text, String
      const :type, String
    end

    class Commit < T::Struct
      const :abbreviatedOid, String
    end

    class PullRequestCommit < T::Struct
      const :commit, Commit
    end

    class ThreadSubject < T::Struct
      const :diffLines, T.nilable(T::Array[DiffLine])
      const :endLine, T.nilable(Numeric)
      const :endDiffSide, T.nilable(PullRequests::PageData::ThreadPreviews::Loader::DiffSide)
      const :originalEndLine, T.nilable(Numeric)
      const :originalStartLine, T.nilable(Numeric)
      const :pullRequestCommit, T.nilable(PullRequestCommit)
      const :startDiffSide, T.nilable(PullRequests::PageData::ThreadPreviews::Loader::DiffSide)
      const :startLine, T.nilable(Numeric)
    end

    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    class CommentPreview < T::Struct
      const :author, T.nilable(Author)
    end

    class CommentsData < T::Struct
      const :comments, T::Array[PullRequests::PageData::ThreadComments::Payload::PullRequestComment]
    end

    class Thread < T::Struct
      const :id, String
      const :isOutdated, T::Boolean
      const :path, T.nilable(String)
      const :subject, ThreadSubject
      const :originalDiffPathUri, T.nilable(String)
      const :diffSide, T.nilable(PullRequests::PageData::ThreadPreviews::Loader::DiffSide)
      const :subjectType, T.nilable(String)
      const :line, T.nilable(Numeric)
      const :startLine, T.nilable(Numeric)
      const :startDiffSide, T.nilable(PullRequests::PageData::ThreadPreviews::Loader::DiffSide)
      const :commentsData, T.nilable(CommentsData)
      const :commentCount, T.nilable(Integer)
    end

    sig do
      params(
        thread_previews: T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      ).returns(T::Array[Thread])
    end
    def self.call(thread_previews)
      new.call(thread_previews)
    end

    sig do
      params(
        thread_previews: T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      ).returns(T::Array[Thread])
    end
    def call(thread_previews)
      thread_previews.map do |thread_preview|
        if thread_preview.first_comment.present?
          first_comment = PullRequests::PageData::ThreadComments::Payload.call(T.must(thread_preview.first_comment)).first
        end

        pull_request_commit = thread_preview.subject.pull_request_commit

        if pull_request_commit.present?
          pull_request_commit_payload = PullRequestCommit.new(
            commit: Commit.new(abbreviatedOid: pull_request_commit)
          )
        end

        # Calculate comment count excluding the comments actually included in commentsData
        comments_included = first_comment ? 1 : 0
        comment_count = thread_preview.thread_comments.size - comments_included

        # rubocop:disable GitHub/ThreadUse
        Thread.new(
          id: thread_preview.id,
          isOutdated: thread_preview.is_outdated,
          path: thread_preview.path,
          subject: ThreadSubject.new(
            diffLines: thread_preview.subject.diff_lines&.map do |diff_line|
              DiffLine.new(
                html: diff_line[:html],
                left: diff_line[:left],
                right: diff_line[:right],
                text: diff_line[:text],
                type: diff_line[:type].to_s.upcase
              )
            end,
            endLine: thread_preview.subject.end_line,
            endDiffSide: thread_preview.subject.end_diff_side,
            originalEndLine: thread_preview.subject.original_end_line,
            originalStartLine: thread_preview.subject.original_start_line,
            pullRequestCommit: pull_request_commit_payload,
            startDiffSide: thread_preview.subject.start_diff_side,
            startLine: thread_preview.subject.start_line
          ),
          originalDiffPathUri: thread_preview.original_diff_path_uri && "#{GitHub.url}#{thread_preview.original_diff_path_uri}",
          diffSide: thread_preview.subject.end_diff_side,
          subjectType: thread_preview.subject_type.to_s.upcase,
          line: thread_preview.line || thread_preview.subject.end_line,
          startLine: thread_preview.subject.start_line,
          startDiffSide: thread_preview.subject.start_diff_side,
          commentsData: first_comment ? CommentsData.new(comments: [first_comment]) : nil,
          commentCount: comment_count
        )
        # rubocop:enable GitHub/ThreadUse
      end
    end
  end
end
