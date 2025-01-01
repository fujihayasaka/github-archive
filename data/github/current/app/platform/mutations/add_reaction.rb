# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddReaction < Platform::Mutations::Base
      description "Adds a reaction to a subject."

      minimum_accepted_scopes ["public_repo", "write:discussion"]

      argument :subject_id, ID, "The Node ID of the subject to modify.", required: true, loads: Interfaces::Reactable
      argument :content, Enums::ReactionContent, "The name of the emoji to react with.", required: true

      field :subject, Interfaces::Reactable, "The reactable subject.", null: true

      field :reaction, Objects::Reaction, "The reaction object.", null: true

      field :reaction_groups, [Objects::ReactionGroup], "The reaction groups for the subject.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, subject:, **inputs)
        reactable = subject.is_a?(::PullRequest) ? subject.issue : subject
        egress_access_role = permission.fetch_reactable_egress_access_role(reactable)

        if reactable.is_a?(::DiscussionPost) || reactable.is_a?(::DiscussionPostReply)
          reactable.async_organization.then do |org|
            current_org = org
            permission.access_allowed?(egress_access_role, organization: org, current_org: current_org, resource: reactable, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          permission.async_repo_and_org_owner(reactable).then do |repo, org|
            permission.access_allowed?(egress_access_role, repo: repo, resource: reactable, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(subject:, **inputs)
        if subject.is_a?(::Issue) || (subject.is_a?(::IssueComment) && !T.must(subject.issue).pull_request?)
          if subject.repository && !T.must(subject.repository).has_issues?
            raise Errors::Forbidden, "Issues are disabled on this repository"
          end
        end

        reactable = subject.is_a?(::PullRequest) ? subject.issue : subject

        if context[:viewer].blocked_by?(reactable.reaction_admin)
          raise Errors::Forbidden, "User is blocked from reacting to this subject."
        end

        if reactable.async_reactions_locked_for?(context[:viewer]).sync
          raise Errors::Forbidden, "User can not react to locked subject."
        end

        if reactable.is_a?(::Issue) || reactable.is_a?(::IssueComment)
          check_database_resource_update_rate_limit!(resource: reactable, current_user: context[:viewer])
        end

        reaction = reactable.react(actor: context[:viewer], content: inputs[:content])

        unless reaction.valid?
          raise Errors::Unprocessable.new(
            "Could not add reaction to #{subject.class.name} with ID #{subject.global_relay_id}.",
          )
        end

        reaction_groups = reactable.reaction_groups

        { subject: subject, reaction: reaction, reaction_groups: reaction_groups }
      end
    end
  end
end
