# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RecentInteraction < Platform::Objects::Base
      description "A record that a user has recently interacted with."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # Permissions found here are similar to api access permissions
        # in Objects::Issue and Objects::PullRequest
        pull_or_issue = object.interactable

        if pull_or_issue.is_a?(::PullRequest)
          permission.async_repo_and_org_owner(pull_or_issue).then do |repo, org|
            pull_or_issue.async_issue.then do
              permission.access_allowed?(
                :get_pull_request,
                resource: pull_or_issue,
                repo: repo,
                current_org: org,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
              )
            end
          end
        else
          permission.async_repo_and_org_owner(pull_or_issue).then do |repo, org|
            pull_or_issue.async_pull_request.then do
              permission.access_allowed?(
                :show_issue,
                resource: pull_or_issue,
                repo: repo,
                current_org: org,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
                # Allow issues on public repos to be returned even when the current GitHub app isn't installed on the repo
                approved_integration_required: false,
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if object.pull_request?
          permission.typed_can_see?("PullRequest", object.interactable)
        else
          permission.typed_can_see?("Issue", object.interactable)
        end
      end

      required_capabilities [:mobile_only_schema_mask]

      scopeless_tokens_as_minimum

      field :interactable, Unions::IssueOrPullRequest, "The record with which the user interacted.", null: false
      field :interaction, Enums::InteractionType, "A description of how the user interacted with the record.", null: false
      field :occurred_at, Scalars::DateTime, "When the interaction occurred.", null: false
      field :commenter, Objects::User, "User who left a comment if the interaction is as comment.", null: true
      field :comment_id, Integer, "Id of the comment if the interaction is on a comment.", null: true
    end
  end
end
