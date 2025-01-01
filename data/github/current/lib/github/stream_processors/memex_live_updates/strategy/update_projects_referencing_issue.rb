# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class UpdateProjectsReferencingIssue < Base
          ISSUE_UPDATE_TOPICS = [
            /github\.v1\.IssueUpdateAssignee\Z/,
            /github\.v1\.IssueUpdateIssueType\Z/,
            /github\.v1\.IssueUpdateLabel\Z/,
          ]

          def self.topics
            ISSUE_UPDATE_TOPICS
          end

          def execute_strategy!
            matching_project_items = with_readonly_database_connection do
              MemexProjectItem
                .includes(:memex_project)
                .where(repository_id: @message.repository_id, content_id: @message.content_id, content_type: @message.content_type)
                .to_a
            end

            if matching_project_items.empty?
              return Result.new(error_message: "No memex project items found")
            end

            matching_project_items.each do |memex_project_item|
              emit_socket_message_for_memex_project(
                memex_project_item.memex_project,
                @message.topic,
                {
                  payload: {
                    memex_project_item_id: memex_project_item.id,
                  },
                  actor: {
                    id: safe_actor.id,
                  },
                }
              )
            end

            Result.new(sockets_updated: matching_project_items.length)
          end
        end
      end
    end
  end
end
