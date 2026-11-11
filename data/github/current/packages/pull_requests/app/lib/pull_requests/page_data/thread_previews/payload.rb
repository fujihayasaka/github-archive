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

    class PreviewInfo < T::Struct
      const :firstComment, T.nilable(PullRequests::PageData::ThreadComments::Payload::PullRequestComment)
      const :threadId, String
      #TODO: send isOutdated to accurately reflect comment status
      const :path, String
      const :subject, ThreadSubject
      const :threadPreviewComments, T::Array[CommentPreview]
      const :originalDiffPathUri, T.nilable(String)
    end

    class ThreadPreview < T::Struct
      const :previewInfo, T::nilable(PreviewInfo)
    end

    sig do
      params(
        thread_previews: T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      ).returns(T::Array[ThreadPreview])
    end
    def self.call(thread_previews)
      new.call(thread_previews)
    end

    sig do
      params(
        thread_previews: T::Array[PullRequests::PageData::ThreadPreviews::Loader::ThreadPreview]
      ).returns(T::Array[ThreadPreview])
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
        ThreadPreview.new(
          previewInfo: PreviewInfo.new(
            firstComment: first_comment,
            threadId: thread_preview.id,
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
            threadPreviewComments: thread_preview.thread_comments.drop(1).map do |comment|
              author = comment.user
              if author.present?
                author_payload = Author.new(
                  login: author.display_login,
                  avatarUrl: author.primary_avatar_url
                )
              end

              CommentPreview.new(
                author: author_payload
              )
            end,
            originalDiffPathUri: thread_preview.original_diff_path_uri && "#{GitHub.url}#{thread_preview.original_diff_path_uri}"
          )
        )
      end
    end
  end
end
