# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CloseDiscussion < Platform::Mutations::Base
      description "Close a discussion."
      minimum_accepted_scopes ["public_repo"]

      argument :discussion_id,
        ID,
        description: "ID of the discussion to be closed.",
        required: true,
        loads: Objects::Discussion

      argument :reason,
        Enums::DiscussionCloseReason,
        description: "The reason why the discussion is being closed.",
        default_value: "resolved",
        required: false

      field :discussion,
        Objects::Discussion,
        description: "The discussion that was closed.",
        null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :close_discussion,
            repo: repo,
            current_org: org,
            resource: discussion,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      sig do
        params(
          discussion: Discussion,
          reason: String,
        ).returns(T::Hash[Symbol, Discussion])
      end
      def resolve(discussion:, reason:)
        if discussion.close(
          actor: context[:viewer],
          reason: Discussion::StateReasonable::CloseReason.deserialize(reason),
        )
          { discussion: discussion }
        else
          raise Errors::Unprocessable.new("Unable to close this discussion.")
        end
      end
    end
  end
end
