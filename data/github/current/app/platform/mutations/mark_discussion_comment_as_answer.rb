# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkDiscussionCommentAsAnswer < Platform::Mutations::Base
      description "Mark a discussion comment as the chosen answer for discussions in an answerable category."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the discussion comment to mark as an answer.",
        required: true, loads: Objects::DiscussionComment, as: :comment

      field :discussion, Objects::Discussion, "The discussion that includes the chosen comment.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        comment.async_discussion.then do |discussion|
          permission.async_repo_and_org_owner(discussion).then do |repo, org|
            permission.access_allowed?(
              :answer_discussion,
              repo: repo,
              current_org: org,
              resource: discussion,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          end
        end
      end

      FALLBACK_ERROR_PHRASE = "may not be marked as the answer at this time"

      def resolve(comment:)
        discussion = comment.discussion

        if reason = comment.disallow_marking_as_answer_reason
          # Do nothing and report success if this comment is already the answer to make this mutation idempotent.
          return { discussion: discussion } if reason == :already_marked

          phrase = DiscussionComment::DISALLOW_REASONS.fetch(reason, FALLBACK_ERROR_PHRASE)
          raise Errors::Unprocessable.new("Comment '#{comment.global_relay_id}' #{phrase}.")
        end

        # Pass actor so that timeline and Hydro events will be generated
        unless comment.mark_as_answer(actor: context[:viewer], performed_via_integration: context[:integration])
          # mark_as_answer doesn't fail with model validation errors, so let's handle this generically.
          raise Errors::Unprocessable.new("Comment '#{comment.global_relay_id}' #{FALLBACK_ERROR_PHRASE}.")
        end

        { discussion: discussion }
      end
    end
  end
end
