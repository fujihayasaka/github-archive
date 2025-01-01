# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReopenDiscussion < Platform::Mutations::Base
      extend T::Sig

      description "Reopen a discussion."
      minimum_accepted_scopes ["public_repo"]

      argument :discussion_id,
        ID,
        description: "ID of the discussion to be reopened.",
        required: true,
        loads: Objects::Discussion

      field :discussion,
        Objects::Discussion,
        description: "The discussion that was reopened.",
        null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :reopen_discussion,
            repo: repo,
            current_org: org,
            resource: discussion,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      sig { params(discussion: Discussion).returns(T::Hash[Symbol, Discussion]) }
      def resolve(discussion:)
        if discussion.reopen(actor: context[:viewer])
          { discussion: discussion }
        else
          raise Errors::Unprocessable.new("Unable to reopen this discussion.")
        end
      end
    end
  end
end
