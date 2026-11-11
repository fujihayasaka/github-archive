# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class UpdateParentProject < Base
          PROJECT_ITEM_TOPICS = [
            /github\.memex\.v0\.ProjectItemCreate\Z/,
            /github\.memex\.v0\.ProjectItemUpdate\Z/,
            /github\.memex\.v0\.ProjectItemDestroy\Z/,
          ]

          COLUMN_VALUE_TOPICS = [
            /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/,
            /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/,
            /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/,
            /github\.memex\.v0\.MemexProjectItemMove\Z/,
          ]

          PROJECT_TOPICS = [
            /github\.memex\.v0\.MemexProjectEvent\Z/,
          ]

          VIEW_TOPICS = [
            /github\.memex\.v0\.MemexProjectViewCreate\Z/,
            /github\.memex\.v0\.MemexProjectViewUpdate\Z/,
            /github\.memex\.v0\.MemexProjectViewDestroy\Z/
          ]

          COLUMN_TOPICS = [
            /github\.memex\.v1\.MemexProjectColumnCreate\Z/,
            /github\.memex\.v1\.MemexProjectColumnUpdate\Z/,
            /github\.memex\.v1\.MemexProjectColumnDestroy\Z/
          ]

          def self.topics
            PROJECT_ITEM_TOPICS +
            PROJECT_TOPICS +
            COLUMN_VALUE_TOPICS +
            VIEW_TOPICS +
            COLUMN_TOPICS
          end

          def execute_strategy!
            memex_project = with_readonly_database_connection do
              MemexProject.find_by(id: @message.memex_project_id)
            end

            unless memex_project
              return Result.new(error_message: "No memex project found")
            end

            emit_socket_message_for_memex_project(
              memex_project,
              @message.topic,
              socket_message_data
            )

            Result.new(sockets_updated: 1)
          end

          private def socket_message_data
            payload = \
              case @message.topic
              when *PROJECT_ITEM_TOPICS
                { id: @message.memex_project_item_id }
              when *COLUMN_VALUE_TOPICS
                {
                  column_id: @message.memex_project_column_id,
                  item_id: @message.memex_project_item_id,
                }
              when *PROJECT_TOPICS
                { id: @message.memex_project_id }
              when *VIEW_TOPICS
                { memex_project_view_id: @message.memex_project_view_id }
              when *COLUMN_TOPICS
                { memex_project_column_id: @message.memex_project_column_id }
              end

            {
              payload: payload,
              actor: {
                id: safe_actor.id,
              },
            }
          end
        end
      end
    end
  end
end
