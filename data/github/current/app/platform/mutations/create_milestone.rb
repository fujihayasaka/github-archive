# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateMilestone < Platform::Mutations::Base
      description "Creates a new milestone."
      visibility :internal
      feature_flag :issues_react_create_milestone

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :title, String, "Identifies the title of the milestone.", required: true
      argument :due_on, Scalars::DateTime, "Identifies the due date of the milestone.", required: false
      argument :description, String, "Identifies the description of the milestone.", required: false

      error_fields
      field :milestone, Objects::Milestone, "The new milestone.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :create_milestone, current_org: org, repo: repository, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(repository:, execution_errors:, **inputs)
        authorization = ContentAuthorizer::MilestoneAuthorizer.new(context[:viewer], :create, repository: repository)
        if authorization.failed?
          raise Errors::Unprocessable.new(authorization.error_messages)
        end

        milestone = repository.milestones.build
        milestone.title = inputs[:title]
        milestone.due_on = inputs[:due_on]
        milestone.description = inputs[:description]
        milestone.created_by = context[:viewer]

        if milestone.save
          {
            milestone: milestone,
            errors: [],
          }
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
