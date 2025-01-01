# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnvironment < Platform::Mutations::Base
      description "Updates an environment."

      minimum_accepted_scopes ["public_repo"]

      argument :environment_id, ID, "The node ID of the environment.", required: true, loads: Objects::Environment, as: :environment
      argument :wait_timer, Int, "The wait timer in minutes.", required: false
      argument :reviewers, [ID], "The ids of users or teams that can approve deployments to this environment", required: false
      argument :prevent_self_review, Boolean, "Whether deployments to this environment can be approved by the user who created the deployment.", required: false

      field :environment, Objects::Environment, "The updated environment.", null: true
      error_fields
      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, environment:, **inputs)
        repo = environment.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_actions_environments_repo,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, environment:, **inputs)
        unless inputs[:reviewers].nil?
          if inputs[:reviewers].any?
            actors = inputs[:reviewers].map do |reviewer_id|
              Platform::Helpers::NodeIdentification.typed_object_from_id(
                [Platform::Objects::User, Platform::Objects::Team],
                reviewer_id,
                context,
              )
            end
            environment.create_or_update_approval_gate(actors, prevent_self_review: inputs[:prevent_self_review])
          else
            environment.remove_approval_gate
          end
        end

        if !inputs[:prevent_self_review].nil? && inputs[:reviewers].nil?
          environment.create_or_update_approval_gate(nil, prevent_self_review: inputs[:prevent_self_review])
        end

        if inputs[:wait_timer].present?
          if inputs[:wait_timer] > 0
            environment.create_or_update_wait_gate(inputs[:wait_timer])
          else
            environment.remove_wait_gate
          end
        end

        if environment.errors.present?
          Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(environment.errors.full_messages), execution_errors)
          return { environment: nil, errors: Platform::UserErrors.mutation_errors_for_model(environment) }
        end

        { environment: environment, errors: [] }
      end
    end
  end
end
