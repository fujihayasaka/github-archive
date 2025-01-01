# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddUpvote < Platform::Mutations::Base
      description "Add an upvote to a discussion or discussion comment."
      minimum_accepted_scopes ["public_repo"]

      argument :subject_id, ID, "The Node ID of the discussion or comment to upvote.",
        required: true, loads: Interfaces::Votable

      field :subject, Interfaces::Votable, "The votable subject.", null: true
      error_fields

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, subject:, **inputs)
        permission.async_repo_and_org_owner(subject).then do |repo, org|
          permission.access_allowed?(
            :toggle_upvote,
            repo: repo,
            current_org: org,
            resource: subject,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      def resolve(subject:, execution_errors:, **inputs)
        vote = subject.upvote(context[:viewer])
        if vote.errors.any?
          error_names = vote.errors.attribute_names
          client_errors = error_names.map do |attribute|
            vote.errors[attribute].map do |error_message|
              {
                path: [],
                message: vote.errors.full_message(attribute, error_message),
                short_message: error_message,
                attribute: attribute.to_s,
              }
            end
          end

          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(vote, execution_errors)
          { subject: nil, errors: client_errors.flatten }
        else
          { subject: subject.reload, errors: [] }
        end
      end
    end
  end
end
