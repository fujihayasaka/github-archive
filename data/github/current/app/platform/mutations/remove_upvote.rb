# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveUpvote < Platform::Mutations::Base
      description "Remove an upvote to a discussion or discussion comment."
      minimum_accepted_scopes ["public_repo"]

      argument :subject_id, ID, "The Node ID of the discussion or comment to remove upvote.",
        required: true, loads: Interfaces::Votable

      field :subject, Interfaces::Votable, "The votable subject.", null: true
      error_fields


      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, subject:)
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

      def resolve(subject:)
        vote = subject.vote_by(context[:viewer], upvote: true)
        return { subject: subject, errors: [] } if vote.nil?

        if vote.destroy
          { subject: subject.reload, errors: [] }
        else
          raise Platform::Errors::Unprocessable, "Unable to remove vote at this time"
        end
      end
    end
  end
end
