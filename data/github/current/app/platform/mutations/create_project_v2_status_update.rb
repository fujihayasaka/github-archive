# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProjectV2StatusUpdate < Platform::Mutations::Base
      description "Creates a status update within a Project."

      minimum_accepted_scopes ["project"]

      argument :project_id, ID, "The ID of the Project to create the status update in.", required: true, loads: Objects::ProjectV2
      argument :start_date, Platform::Scalars::Date, "The start date of the status update.", required: false
      argument :target_date, Platform::Scalars::Date, "The target date of the status update.", required: false
      argument :status, Platform::Enums::ProjectV2StatusUpdateStatus, "The status of the status update.", required: false
      argument :body, String, description: "The body of the status update.", required: false

      field :status_update, Objects::ProjectV2StatusUpdate, "The status update updated in the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        project.async_owner.then do |owner|
          current_org = owner if owner.organization?
          permission.access_allowed?(
            :project_v2_write,
            current_org: current_org,
            resource: project,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, **inputs)
        create_params = {
          body: inputs[:body],
          start_date: inputs[:start_date],
          target_date: inputs[:target_date]
        }
        if inputs.key?(:status)
          if inputs[:status].nil?
            create_params[:status_id] = nil
          else
            status_id = MemexProjectStatus.status_enum_string_to_id(inputs[:status])
            raise Errors::Validation.new("Unexpected status update status: #{inputs[:status]}") unless status_id
            create_params[:status_id] = status_id
          end
        end

        status_update = MemexProjectStatus.build_for_project(project, context[:viewer], create_params)
        if status_update.save
          { status_update: status_update }
        else
          raise Errors::Unprocessable.new(status_update.errors.full_messages.join(", "))
        end
      end
    end
  end
end
