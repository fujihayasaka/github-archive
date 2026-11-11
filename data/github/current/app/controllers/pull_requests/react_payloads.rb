# typed: true
# frozen_string_literal: true

module PullRequests
  module ReactPayloads
    class PullRequestsLayoutPayload < ReactPayload::Base
      def route_id
        "pullRequestsLayoutRoute"
      end

      sig { params(header_data: T::Hash[String, T.untyped]).void }
      def initialize(header_data)
        @header_data = header_data
      end

      def payload
        @header_data
      end
    end

    class PullRequestsCommitsPayload < ReactPayload::Base
      def route_id
        "pullRequestsCommitsRoute"
      end

      sig { params(commits_data: T::Hash[String, T.untyped]).void }
      def initialize(commits_data)
        @commits_data = commits_data
      end

      def payload
        @commits_data
      end
    end

    class PullRequestsFilesPayload < ReactPayload::Base
      def route_id
        "pullRequestsFilesRoute"
      end

      sig { params(files_data: T::Hash[String, T.untyped]).void }
      def initialize(files_data)
        @files_data = files_data
      end

      def payload
        @files_data
      end
    end

    class PullRequestsFilesWithRangePayload < ReactPayload::Base
      def route_id
        "pullRequestsFilesWithRangeRoute"
      end

      sig { params(files_data: T::Hash[String, T.untyped]).void }
      def initialize(files_data)
        @files_data = files_data
      end

      def payload
        @files_data
      end
    end

    class PullRequestsChangesPayload < ReactPayload::Base
      def route_id
        "pullRequestsChangesRoute"
      end

      sig { params(files_data: T::Hash[String, T.untyped]).void }
      def initialize(files_data)
        @files_data = files_data
      end

      def payload
        @files_data
      end
    end

    class PullRequestsChangesWithRangePayload < ReactPayload::Base
      def route_id
        "pullRequestsChangesWithRangeRoute"
      end

      sig { params(files_data: T::Hash[String, T.untyped]).void }
      def initialize(files_data)
        @files_data = files_data
      end

      def payload
        @files_data
      end
    end

    class PullRequestsOverviewPayload < ReactPayload::Base
      def route_id
        "pullRequestsOverviewRoute"
      end

      sig { params(overview_data: T::Hash[String, T.untyped]).void }
      def initialize(overview_data)
        @overview_data = overview_data
      end

      def payload
        @overview_data
      end
    end

    class PullRequestsConversationsPayload < ReactPayload::Base
      def route_id
        "pullRequestsConversationsRoute"
      end

      sig do
        params(
          locked: T::Boolean,
          pull_request: T.untyped,
          current_user: T.nilable(::User),
          default_merge_method: T.any(String, Symbol)
        ).void
      end
      def initialize(locked:, pull_request:, current_user:, default_merge_method:)
        @locked = locked
        @pull_request = pull_request
        @current_user = current_user
        @default_merge_method = default_merge_method
      end

      def payload
        {
          aliveChannel: ::GitHub::WebSocket.signed_channel(GitHub::WebSocket::Channels.pull_request_timeline(@pull_request)),
          markAsReadChannel: @current_user ? GitHub::WebSocket.signed_channel((GitHub::WebSocket::Channels.marked_as_read(@current_user))) : nil,
          id: @pull_request.global_relay_id,
          locked: @locked,
          helpUrl: GitHub.help_url,
          defaultMergeMethod: @default_merge_method,
          mergeboxChannels: PullRequests::PageData::MergeBox::PullRequestPayload::MergeBoxAliveChannels.new(
            stateChannel: GitHub::WebSocket::Channels.signed_pull_request_state(@pull_request),
            deployedChannel: GitHub::WebSocket::Channels.signed_pull_request_deployed(@pull_request),
            reviewStateChannel: GitHub::WebSocket::Channels.signed_pull_request_review_state(@pull_request),
            workflowsChannel: GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(@pull_request),
            mergeQueueChannel:  GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(@pull_request),
            headRefChannel: @pull_request.head_repository ? GitHub::WebSocket::Channels.signed_branch(@pull_request.head_repository, @pull_request.display_head_ref_name) : nil,
            baseRefChannel: GitHub::WebSocket::Channels.signed_branch(@pull_request.base_repository, @pull_request.display_base_ref_name),
            gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(@pull_request),
            pullRequestChannel: GitHub::WebSocket::Channels.signed_pull_request(@pull_request)
          ),
        }
      end
    end

    class PullRequestsConversationsPartialPayload < ReactPayload::VoltronPartial
      def route_id
        "pullRequestsConversationsRoute.Conversation"
      end
    end

    class PullRequestsConversationsBodyPayload < ReactPayload::Partial
      def route_id
        "pullRequestsConversationsRoute.Body"
      end
    end

    class PullRequestsConversationsTimelinePayload < ReactPayload::VoltronPartial
      def route_id
        "pullRequestsConversationsRoute.Timeline"
      end
    end

    class PullRequestsConversationsSidebarPartialPayload < ReactPayload::VoltronPartial
      def route_id
        "pullRequestsConversationsRoute.Sidebar"
      end
    end

    class PullRequestsConversationsTimelineActionsPartialPayload < ReactPayload::Partial
      def route_id
        "pullRequestsConversationsRoute.TimelineActions"
      end
    end

    class PullRequestsChecksPartialPayload < ReactPayload::Partial
      def route_id
        "pullRequestsChecksRoute.Main"
      end
    end
  end
end
