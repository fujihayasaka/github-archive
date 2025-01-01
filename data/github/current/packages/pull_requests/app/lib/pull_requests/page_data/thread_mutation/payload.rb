# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadMutation
  class Payload
    class ThreadMutationResponse < T::Struct
      const :thread, PullRequests::PageData::Files::Payload::ThreadWithComments
      const :comment, PullRequests::PageData::ThreadComments::Payload::PullRequestComment
    end

    sig do
      params(
        thread_mutation_data: PullRequests::PageData::ThreadMutation::Loader::ThreadMutationData
      ).returns(ThreadMutationResponse)
    end
    def self.call(thread_mutation_data)
      new.call(thread_mutation_data)
    end

    sig do
      params(
        thread_mutation_data: PullRequests::PageData::ThreadMutation::Loader::ThreadMutationData
      ).returns(ThreadMutationResponse)
    end
    def call(thread_mutation_data)
      ThreadMutationResponse.new(
      thread: PullRequests::PageData::Files::Payload::ThreadWithComments.new( # rubocop:disable GitHub/ThreadUse
        id: thread_mutation_data.thread.id.to_s,
        isResolved: thread_mutation_data.thread.is_resolved,
        subjectType: thread_mutation_data.thread.subject_type,
        viewerCanReply: thread_mutation_data.thread.viewer_can_reply,
        commentsData: PullRequests::PageData::Files::Payload::CommentsData.new({
          comments: PullRequests::PageData::ThreadComments::Payload.call(thread_mutation_data.thread.thread_comments),
          __id: thread_mutation_data.thread.id.to_s,
        }),
        reviewCommentsLimit: thread_mutation_data.limit_config.review_comments_per_thread_limit,
        # Do not limit review comments in response to mutation
        reviewCommentsLimitExceeded: false,
      ),
      comment: T.must(PullRequests::PageData::ThreadComments::Payload.call(thread_mutation_data.comment).first),
    )
    end
  end
end
