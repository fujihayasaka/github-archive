# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module MergeBox
      class AliveChannelsPayload
        class Data < T::Struct
          const :stateChannel, String
          const :deployedChannel, String
          const :reviewStateChannel, String
          const :workflowsChannel, String
          const :codeScanningChannel, T.nilable(String)
          const :mergeQueueChannel, String
          const :headRefChannel, T.nilable(String)
          const :baseRefChannel, String
          const :gitMergeStateChannel, String
          const :pullRequestChannel, String
        end

        sig { params(pull_request: PullRequest, base_repository: Repository, head_repository: T.nilable(Repository)).returns(Data) }
        def self.build(pull_request:, base_repository:, head_repository: nil)
          Data.new(
            stateChannel: GitHub::WebSocket::Channels.signed_pull_request_state(pull_request),
            deployedChannel: GitHub::WebSocket::Channels.signed_pull_request_deployed(pull_request),
            reviewStateChannel: GitHub::WebSocket::Channels.signed_pull_request_review_state(pull_request),
            workflowsChannel: GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(pull_request),
            codeScanningChannel: FeatureFlag.vexi.enabled?(:pull_request_code_scanning_channel, base_repository, default: false) ? GitHub::WebSocket::Channels.signed_pull_request_code_scanning_state(pull_request) : nil,
            mergeQueueChannel:  GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(pull_request),
            headRefChannel: head_repository ? GitHub::WebSocket::Channels.signed_branch(head_repository, pull_request.display_head_ref_name) : nil,
            baseRefChannel: GitHub::WebSocket::Channels.signed_branch(base_repository, pull_request.display_base_ref_name),
            gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(pull_request),
            pullRequestChannel: GitHub::WebSocket::Channels.signed_pull_request(pull_request)
          )
        end
      end
    end
  end
end
