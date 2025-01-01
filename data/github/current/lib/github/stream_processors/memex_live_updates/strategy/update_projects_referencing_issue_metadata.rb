# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class UpdateProjectsReferencingIssueMetadata < Base
          BATCH_SIZE = 100

          LABEL_UPDATE_TOPIC = /github\.v1\.LabelUpdate\Z/

          def self.topics
            [
              LABEL_UPDATE_TOPIC,
            ]
          end

          def execute_strategy!
            with_readonly_database_connection do
              affected_memex_projects.each do |project|
                emit_socket_message_for_memex_project(
                  project,
                  @message.topic,
                  {
                    payload: {
                      memex_project_id: project.id,
                    }.merge(identifier_attributes),
                    actor: {
                      id: safe_actor.id,
                    },
                  }
                )
              end
            end

            Result.new(
              sockets_updated: affected_memex_projects.length,
              error_message: affected_memex_projects.length > 0 ? nil : "No memex project items found"
            )
          end

          private def affected_memex_projects
            return @affected_memex_projects if defined?(@affected_memex_projects)

            @affected_memex_projects = batched_issue_id_iterator.reduce(Set.new) do |projects, batch|
              projects.merge(
                MemexProjectItem
                  .includes(:memex_project)
                  .select(:id, :memex_project_id)
                  .where(issue_id: batch.map(&:issue_id))
                  .group(:memex_project_id)
                  .map(&:memex_project)
              )
            end
          end

          private def batched_issue_id_iterator
            case @message.topic
            when LABEL_UPDATE_TOPIC
              IssuesLabels
                .select(:issue_id)
                .where(identifier_attributes)
                .in_batches(of: BATCH_SIZE)
            end
          end

          private def identifier_attributes
            case @message.topic
            when LABEL_UPDATE_TOPIC
              { label_id: @message.dig(:label, :label_id) }
            end
          end
        end
      end
    end
  end
end
