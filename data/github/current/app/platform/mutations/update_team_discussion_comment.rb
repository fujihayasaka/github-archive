# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamDiscussionComment < Platform::Mutations::Base
      description "Updates a discussion comment."

      minimum_accepted_scopes ["write:discussion"]

      argument :id, ID, "The ID of the comment to modify.", required: true, loads: Objects::TeamDiscussionComment, as: :comment
      argument :body, String, "The updated text of the comment.", required: true
      argument :body_version, String, "The current version of the body content.", required: false

      field :team_discussion_comment, Objects::TeamDiscussionComment, "The updated comment.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        comment.async_organization.then do |org|
          permission.access_allowed?(
            :update_team_discussion_comment,
            resource: comment,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(comment:, **inputs)

        unless comment.async_viewer_can_update?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to update the comment #{comment.global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        if (version = inputs[:body_version]) && version != comment.body_version
          raise Errors::StaleData.new({
            stale: true,
            updated_markdown: comment.body,
            updated_html: comment.body_html,
            version: comment.body_version,
          }.to_json)
        end

        comment.update_body(inputs[:body], context[:viewer])

        if comment.valid?
          { team_discussion_comment: comment }
        else
          raise Errors::Validation.new(comment.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
