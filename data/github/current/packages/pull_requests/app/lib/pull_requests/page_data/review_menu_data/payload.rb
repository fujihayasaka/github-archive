# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ReviewMenuData
  class Payload
    class ReviewMenuPayload < T::Struct
      const :viewerHasViolatedPushPolicy, T::Boolean
      const :viewerIsCopilotAttributed, T::Boolean
      const :viewerPermission, PullRequests::PageData::ReviewMenuData::Loader::ViewerPermission
      const :threads, T::Array[PullRequests::PageData::Threads::Payload::ThreadWithComments]
    end

    sig do
      params(
        loader_data: PullRequests::PageData::ReviewMenuData::Loader::ReviewMenuData
      ).returns(ReviewMenuPayload)
    end
    def self.call(loader_data)
      new(loader_data).call
    end

    sig { params(loader_data: PullRequests::PageData::ReviewMenuData::Loader::ReviewMenuData).void }
    def initialize(loader_data)
      @loader_data = loader_data
    end

    sig { returns(ReviewMenuPayload) }
    def call
      threads_result = PullRequests::PageData::Threads::Payload.call(
        thread_data_items: @loader_data.threads,
      )

      ReviewMenuPayload.new(
        viewerHasViolatedPushPolicy: @loader_data.viewer_has_violated_push_policy,
        viewerIsCopilotAttributed: @loader_data.viewer_is_copilot_attributed,
        viewerPermission: @loader_data.viewer_permission,
        threads: threads_result.threads,
      )
    end
  end
end
