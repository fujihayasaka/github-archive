# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Payload
    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
    end

    class CommentPreview < T::Struct
      const :author, T.nilable(Author)
    end

    class ThreadPreview < T::Struct
      const :firstComment, T.nilable(PullRequests::PageData::ThreadComments::Payload::PullRequestComment)
      const :line, T.nilable(Numeric)
      const :id, String
      const :isOutdated, T::Boolean
      const :isResolved, T::Boolean
      const :path, String
      const :threadPreviewComments, T::Array[CommentPreview]
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
      thread_previews.map do |thread|
        if thread.first_comment.present?
          first_comment = PullRequests::PageData::ThreadComments::Payload.call(T.must(thread.first_comment)).first
        end

        ThreadPreview.new(
          firstComment: first_comment,
          line: thread.line,
          id: thread.id,
          isOutdated: thread.is_outdated,
          isResolved: thread.is_resolved,
          path: thread.path,
          threadPreviewComments: thread.thread_comments.drop(1).map do |comment|
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
          end
        )
      end
    end
  end
end
