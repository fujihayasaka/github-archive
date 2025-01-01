# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      class Message
        extend Forwardable
        def_delegators :@message, :envelope, :retries, :skip, :success, :error, :timestamp, :value

        def initialize(message)
          @message = message
        end

        def topic
          @message.source_message.topic
        end

        def partition
          @message.source_message.partition
        end

        def actor_id
          dig(:actor, :id)
        end

        def memex_project_id
          dig(:project, :id) || dig(:memex_project, :id)
        end

        def memex_project_column_id
          dig(:project_column, :id) || dig(:memex_project_column, :id)
        end

        def memex_project_item_id
          dig(:project_item, :id) || dig(:memex_project_item, :id)
        end

        def memex_project_view_id
          dig(:project_view, :id)
        end

        def content_id
          dig(:pull_request, :id) || dig(:issue, :id)
        end

        def content_type
          dig(:pull_request, :id) ? "PullRequest" : "Issue"
        end

        def repository_id
          dig(:repository, :id)
        end

        def dig(*path)
          @message.value.dig(*path)
        end
      end
    end
  end
end
