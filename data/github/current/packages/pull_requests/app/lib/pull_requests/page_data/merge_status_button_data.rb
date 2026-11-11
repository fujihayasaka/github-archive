# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class MergeStatusButtonData
    include GitHub::ResilienceMixin

    sig do
      params(pull_request: PullRequest, viewer: User).void
    end
    def initialize(pull_request:, viewer:)
      @pull_request = pull_request
      @viewer = viewer
    end

    sig { returns(PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels) }
    def channels
      @channels ||= T.let(PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels.new(
        stateChannel: GitHub::WebSocket::Channels.signed_pull_request_state(@pull_request),
        deployedChannel: GitHub::WebSocket::Channels.signed_pull_request_deployed(@pull_request),
        reviewStateChannel: GitHub::WebSocket::Channels.signed_pull_request_review_state(@pull_request),
        workflowsChannel: GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(@pull_request),
        mergeQueueChannel: GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(@pull_request),
        headRefChannel: @pull_request.head_repository ? GitHub::WebSocket::Channels.signed_branch(@pull_request.head_repository, @pull_request.display_head_ref_name) : nil,
        baseRefChannel: GitHub::WebSocket::Channels.signed_branch(@pull_request.base_repository, @pull_request.display_base_ref_name),
        gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(@pull_request),
        pullRequestChannel: GitHub::WebSocket::Channels.signed_pull_request(@pull_request)
      ), T.nilable(PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels))
    end

    sig { returns(PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod) }
    def default_merge_method
      @default_merge_method ||= T.let(
        PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod.deserialize(
          with_async_database_error_fallback(
            PullRequest::MergeRequirements.new(@pull_request, nil, nil, nil, @viewer).merge_method,
            fallback: :MERGE
          ).sync.to_s.upcase
        ),
        T.nilable(PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod)
      )
    end

    sig { returns(String) }
    def head_sha
      @pull_request.head_sha
    end

    sig { returns(String) }
    def help_url
      GitHub.help_url
    end

    sig { returns(String) }
    def viewer_login
      @viewer.display_login
    end
  end
end
