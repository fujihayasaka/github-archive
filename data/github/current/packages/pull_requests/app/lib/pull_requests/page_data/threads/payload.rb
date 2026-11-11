# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Threads
  class Payload
    class ThreadsPageInfo < T::Struct
      const :hasNextPage, T::Boolean
      const :cursor, T.nilable(String)
    end

    class CommentsData < T::Struct
      # Diff commenting components expect this to be a Relay-generated ID for appending items to a collection. Since we are not using Relay on the client any longer, we are just passing a value anyway.
      const :__id, String
      const :comments, T::Array[PullRequests::PageData::ThreadComments::Payload::PullRequestComment]
    end

    class ThreadWithComments < T::Struct
      const :id, String
      const :subjectType, String
      const :isResolved, T::Boolean
      const :resolvedBy, T.nilable(String)
      const :viewerCanReply, T::Boolean
      const :commentsData, CommentsData
      const :reviewCommentsLimit, Integer
      const :reviewCommentsLimitExceeded, T::Boolean
      const :pullRequestReviewId, T.nilable(Integer)
    end

    class Result < T::Struct
      const :threads, T::Array[ThreadWithComments]
      const :page_info, T.nilable(ThreadsPageInfo)
    end

    sig do
      params(
        thread_data_items: T::Array[PullRequests::PageData::Threads::Loader::PullRequestThreadData],
        page_info: T.nilable(PullRequests::PageData::Pagination::PageInfo)
      ).returns(Result)
    end
    def self.call(thread_data_items:, page_info: nil)
      new.call(thread_data_items: thread_data_items, page_info: page_info)
    end

    sig do
      params(
        thread_data_items: T::Array[PullRequests::PageData::Threads::Loader::PullRequestThreadData],
        page_info: T.nilable(PullRequests::PageData::Pagination::PageInfo)
      ).returns(Result)
    end
    def call(thread_data_items:, page_info: nil)
      threads = thread_data_items.map do |thread_data|
        comments_payload = PullRequests::PageData::ThreadComments::Payload.call(
          thread_data.thread_comments
        )

        comments_data = CommentsData.new(
          __id: thread_data.id.to_s,
          comments: comments_payload
        )

        ThreadWithComments.new(
          id: thread_data.id.to_s,
          subjectType: thread_data.subject_type.upcase,
          isResolved: thread_data.is_resolved,
          resolvedBy: thread_data.resolved_by&.display_login,
          viewerCanReply: thread_data.viewer_can_reply,
          commentsData: comments_data,
          reviewCommentsLimit: thread_data.review_comments_limit,
          reviewCommentsLimitExceeded: thread_data.review_comments_limit_exceeded,
          pullRequestReviewId: thread_data.pull_request_review_id
        )
      end

      threads_page_info = if page_info
        ThreadsPageInfo.new(
          hasNextPage: page_info.has_next_page,
          cursor: page_info.cursor
        )
      end

      Result.new(
        threads: threads,
        page_info: threads_page_info
      )
    end
  end
end
