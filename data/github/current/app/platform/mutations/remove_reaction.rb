# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveReaction < Platform::Mutations::Base
      description "Removes a reaction from a subject."

      minimum_accepted_scopes ["public_repo", "write:discussion"]

      argument :subject_id, ID, "The Node ID of the subject to modify.", required: true, loads: Interfaces::Reactable, as: :reactable
      argument :content, Enums::ReactionContent, "The name of the emoji reaction to remove.", required: true

      field :subject, Interfaces::Reactable, "The reactable subject.", null: true

      field :reaction, Objects::Reaction, "The reaction object.", null: true

      field :reaction_groups, [Objects::ReactionGroup], "The reaction groups for the subject.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, reactable:, content:, **inputs)
        reactable = reactable.is_a?(::PullRequest) ? reactable.issue : reactable

        association = "#{reactable.class.name.underscore}_reactions"
        extracted_reaction_type = ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(reactable.class.name) ||
                      reactable.is_a?(::Discussion) || reactable.is_a?(::DiscussionComment)

        field = if extracted_reaction_type
          reactable.class.name.underscore
        else
          :subject
        end

        reaction = permission.viewer.send(association).find_by(field => reactable, :content => content)


        if reactable.is_a?(::DiscussionPost) || reactable.is_a?(::DiscussionPostReply)
          reactable.async_organization.then do |org|
            permission.access_allowed?(:delete_team_discussion_related_reaction, organization: org, reaction: reaction, resource: reactable, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          permission.async_repo_and_org_owner(reactable).then do |repo, org|
            permission.access_allowed?(:delete_reaction, repo: repo, reaction: reaction, current_org: org, resource: reactable, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(reactable:, **inputs)
        if reactable.is_a?(::PullRequest)
          pull = reactable
          reactable = reactable.issue
        end

        if context[:viewer].blocked_by?(reactable.reaction_admin)
          raise Errors::Forbidden, "User is blocked from reacting to this subject."
        end

        if reactable.async_reactions_locked_for?(context[:viewer]).sync
          raise Errors::Forbidden, "User can not react to locked subject."
        end

        if reactable.is_a?(::Issue) || reactable.is_a?(::IssueComment)
          check_database_resource_update_rate_limit!(resource: reactable, current_user: context[:viewer])
        end

        reaction = reactable.unreact(actor: context[:viewer], content: inputs[:content])

        # reactable.unreact returns a new record if the reaction does not exist
        # In this scenario, we want to return a NOT_FOUND because calling *any*
        # attribute on that reaction will cause the request to error
        if reaction&.new_record?
          raise Errors::NotFound.new("Could not find a reaction of #{inputs[:content]} on the subject id #{inputs[:subject_id]}")
        end

        unless reaction.status == :deleted
          raise Errors::Unprocessable.new("Could not remove reaction from #{reactable.class.name} with ID #{reactable.id}.")
        end

        reaction_groups = reactable.reaction_groups

        { subject: pull || reactable, reaction: reaction, reaction_groups: reaction_groups }
      end
    end
  end
end
