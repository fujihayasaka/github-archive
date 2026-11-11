# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadMutation
  class Loader
    include PullRequests::PageData::Telemetry
    include GitHub::ResilienceMixin

    class Thread < T::Struct
      const :id, Numeric
      const :is_resolved, T::Boolean
      const :subject_type, String
      const :viewer_can_reply, T::Boolean
      const :thread_comments, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
    end

    class ThreadMutationData < T::Struct
      const :comment, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
      const :thread, Thread
      const :limit_config, PullRequests::PageData::Files::PageLimitConfig
    end

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequestReviewThread) }
    attr_reader :thread

    sig { returns(PullRequestReviewComment) }
    attr_reader :comment

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig do
      params(
        current_user: T.nilable(User),
        thread: PullRequestReviewThread,
        comment: PullRequestReviewComment,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(ThreadMutationData)
    end
    def self.load(current_user:, thread:, comment:, limit_config:, cap_filter: nil)
      new(current_user:, thread:, comment:, limit_config:, cap_filter:).load
    end

    sig do params(
      current_user: T.nilable(User),
      thread: PullRequestReviewThread,
      comment: PullRequestReviewComment,
      limit_config: PullRequests::PageData::Files::PageLimitConfig,
      cap_filter: T.nilable(ConditionalAccess::Web::Filter)
    ).void
    end
    def initialize(current_user:, thread:, comment:, limit_config:, cap_filter: nil)
      @current_user = current_user
      @thread = thread
      @comment = comment
      @limit_config = limit_config
      @cap_filter = cap_filter
    end

    sig { returns(ThreadMutationData) }
    def load
      with_telemetry do
        comments_by_thread_id = PullRequests::PageData::ThreadComments::Loader.load(
          threads: [thread],
          current_user: current_user,
          max_comments: nil,
          comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Default
        )
        comments = comments_by_thread_id[thread.id] || []
        ThreadMutationData.new(
          thread: Thread.new( # rubocop:disable GitHub/ThreadUse
            thread_comments: comments,
            id: thread.id,
            is_resolved: thread.resolved?,
            subject_type: thread.subject_type,
            viewer_can_reply: thread.async_viewer_can_reply?(@current_user).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          ),
          comment: comments.select { |c| c.comment.id == comment.id },
          limit_config: @limit_config,
        )
      end
    end
  end
end
