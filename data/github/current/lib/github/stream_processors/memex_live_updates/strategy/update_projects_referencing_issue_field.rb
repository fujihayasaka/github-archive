# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module MemexLiveUpdates
      module Strategy
        class UpdateProjectsReferencingIssueField < Base
          BATCH_SIZE = 100

          ISSUE_FIELD_OPTION_TOPICS = [
            /github\.v1\.IssueFieldOptionCreate\Z/,
            /github\.v1\.IssueFieldOptionUpdate\Z/,
            /github\.v1\.IssueFieldOptionDestroy\Z/,
          ]

          def self.topics
            ISSUE_FIELD_OPTION_TOPICS
          end

          def execute_strategy!
            unless issue_field_id && issue_field_id > 0
              raise ArgumentError, "Expected message to contain issue_field.id"
            end

            unless issue_field_owner_id
              raise ArgumentError, "Expected message to contain issue_field.owner_id"
            end

            unless issue_field
              return Result.new(
                sockets_updated: 0,
                error_message: "Issue field not found"
              )
            end

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

            Result.new(
              sockets_updated: affected_memex_projects.length,
              error_message: affected_memex_projects.length > 0 ? nil : "No memex project items found"
            )
          end

          private

          def affected_memex_projects
            return @affected_memex_projects if defined?(@affected_memex_projects)

            projects = Set.new

            with_readonly_database_connection do
              MemexProjectColumn
                .includes(:memex_project)
                .where(issue_field_id: issue_field_id)
                .in_batches(of: BATCH_SIZE) do |batch|
                  batch.each do |column|
                    projects << column.memex_project if column.memex_project
                  end
                end
            end

            @affected_memex_projects = projects
          end

          def issue_field_id
            @issue_field_id ||= @message.dig(:issue_field, :id)
          end

          def issue_field_owner_id
            @issue_field_owner_id ||= @message.dig(:issue_field, :owner_id)
          end

          def issue_field_option_id
            @issue_field_option_id ||= @message.dig(:issue_field_option, :id)
          end

          def identifier_attributes
            { issue_field_id: issue_field_id, issue_field_option_id: issue_field_option_id }
          end

          def issue_field
            return @issue_field if defined?(@issue_field)

            @issue_field = with_readonly_database_connection do
              Issues.domain.issue_fields.issue_field_for_org(issue_field_id, issue_field_owner_id)
            end
          end
        end
      end
    end
  end
end
