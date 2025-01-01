# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamDiscussion < Platform::Mutations::Base
      description "Updates a team discussion."

      minimum_accepted_scopes ["write:discussion"]

      argument :id, ID, "The Node ID of the discussion to modify.", required: true, loads: Objects::TeamDiscussion, as: :discussion
      argument :title, String, "The updated title of the discussion.", required: false
      argument :body, String, "The updated text of the discussion.", required: false
      argument :body_version, String, "The current version of the body content. If provided, this update operation will be rejected if the given version does not match the latest version on the server.", required: false
      argument :pinned, Boolean, "If provided, sets the pinned state of the updated discussion.", required: false

      field :team_discussion, Objects::TeamDiscussion, "The updated discussion.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        discussion.async_organization.then do |org|
          permission.access_allowed?(
            :update_team_discussion,
            resource: discussion,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(discussion:, **inputs)

        if ((inputs[:title] || inputs[:body]) &&
            !discussion.async_viewer_can_update?(context[:viewer]).sync)
          message = (
            "#{context[:viewer].display_login} does not have permission to update the discussion #{discussion.global_relay_id}.")
          raise Errors::Forbidden.new(message)
        end

        if !inputs[:pinned].nil? && !discussion.async_viewer_can_pin?(context[:viewer]).sync
          message = (
            "#{context[:viewer].display_login} does not have permission to pin the discussion #{discussion.global_relay_id}.")
          raise Errors::Forbidden.new(message)
        end

        if (version = inputs[:body_version]) && version != discussion.body_version
          raise Errors::StaleData.new({
            stale: true,
            updated_markdown: discussion.body,
            updated_html: discussion.body_html,
            version: discussion.body_version,
          }.to_json)
        end

        discussion.skip_instrument_update = true
        discussion.update_body(inputs[:body], context[:viewer]) if inputs[:body]
        cumulative_changes = discussion.previous_changes

        discussion.title = inputs[:title] if inputs[:title]

        unless inputs[:pinned].nil?
          if inputs[:pinned]
            discussion.pin_by(user_id: context[:viewer].id)
          else
            discussion.unpin
          end
        end

        cumulative_changes = cumulative_changes.merge(discussion.changes)

        if discussion.save
          # We must instrument updates here rather than in an after_commit hook, because
          # UserContentEditable#update_body (called above) commits a separate transaction just to
          # save the body of the discussion, so this resolver as a whole must sometimes make two
          # commits.
          discussion.instrument_update(cumulative_previous_changes: cumulative_changes)
          { team_discussion: discussion }
        else
          raise Errors::Validation.new(discussion.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
