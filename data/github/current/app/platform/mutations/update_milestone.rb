# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateMilestone < Platform::Mutations::Base
      description "Updates an existing milestone."
      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the milestone to be updated.", required: true, loads: Objects::Milestone, as: :milestone
      argument :title, String, "Identifies the title of the milestone.", required: false
      argument :due_on, Scalars::DateTime, "Identifies the due date of the milestone.", required: false
      argument :description, String, "Identifies the description of the milestone.", required: false
      argument :state, Enums::MilestoneState, "Identifies the state of the milestone.", required: false

      error_fields
      field :milestone, Objects::Milestone, "The updated milestone.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, milestone:, **inputs)
        permission.async_owner_if_org(milestone.repository).then do |org|
          permission.access_allowed? :update_milestone, current_org: org, repo: milestone.repository, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(milestone:, execution_errors:, **inputs)
        repository = milestone.repository
        authorization = ContentAuthorizer::MilestoneAuthorizer.new(context[:viewer], :update, repository: repository)
        if authorization.failed?
          raise Errors::Unprocessable.new(authorization.error_messages)
        end

        milestone.title = inputs[:title] if inputs.key?(:title)
        milestone.due_on = inputs[:due_on] if inputs.key?(:due_on)
        milestone.description = inputs[:description] if inputs.key?(:description)
        milestone.state = inputs[:state] if inputs.key?(:state)

        if milestone.save
          { milestone: milestone, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(milestone, execution_errors)
          {
            milestone: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(milestone),
          }
        end
      end
    end
  end
end
