# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Loader
    include GitHub::ResilienceMixin

    class ThreadPreview < T::Struct
      const :first_comment, T.nilable(T::Array[PullRequests::PageData::ThreadComments::Loader::Comment])
      const :line, T.nilable(Numeric)
      const :id, String
      const :is_outdated, T::Boolean
      const :is_resolved, T::Boolean
      const :path, String
      const :thread_comments, T::Array[PullRequestReviewComment]
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(T::Array[ThreadPreview])
    end
    def self.load(current_user:, pull_request:, cap_filter: nil)
      new(current_user:, pull_request:, cap_filter:).load
    end

    sig { params(current_user: T.nilable(User), pull_request: PullRequest, cap_filter: T.nilable(ConditionalAccess::Web::Filter)).void }
    def initialize(current_user:, pull_request:, cap_filter: nil)
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
    end

    sig { returns(T::Array[ThreadPreview]) }
    def load
      with_database_error_fallback(fallback: []) do
        threads = pull_request.review_comment_threads_for(current_user)

        promises = threads.map do |thread|
          PullRequests::PageData::ThreadComments::Loader.load_async(thread: thread, current_user: current_user, max_comments: 1, cap_filter: cap_filter).then do |first_comment|
            ThreadPreview.new(
              first_comment: first_comment,
              line: thread.line,
              id: String(thread.id),
              is_outdated: thread.outdated?,
              is_resolved: thread.resolved?,
              path: thread.path,
              thread_comments: thread.comments.load_target
            )
          end
        end

        Promise.all(promises).sync
      end
    end
  end
end
