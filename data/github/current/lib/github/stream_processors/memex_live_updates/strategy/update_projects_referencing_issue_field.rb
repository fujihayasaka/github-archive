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
              return missing_field_result("Missing issue_field.id", "Expected message to contain issue_field.id")
            end

            unless issue_field_owner_id
              return missing_field_result("Missing issue_field.owner_id", "Expected message to contain issue_field.owner_id")
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

          # When required fields are missing from a message we want to
          # skip gracefully (so the consumer reports this as a skip
          # rather than an error
          def missing_field_result(skip_reason, raise_message)
            if FeatureFlag.vexi.enabled?(:issue_field_option_destroy_cascade_resilience, default: false)
              Result.new(sockets_updated: 0, error_message: skip_reason)
            else
              raise ArgumentError, raise_message
            end
          end

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
            return @issue_field_id if defined?(@issue_field_id)

            @issue_field_id = @message.dig(:issue_field, :id)
            if (@issue_field_id.nil? || @issue_field_id == 0) &&
                FeatureFlag.vexi.enabled?(:issue_field_option_destroy_cascade_resilience, default: false)
              @issue_field_id = @message.dig(:issue_field_option, :issue_field_id)
            end
            @issue_field_id
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
