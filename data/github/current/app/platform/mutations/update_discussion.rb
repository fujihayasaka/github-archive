# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateDiscussion < Platform::Mutations::Base
      description "Update a discussion"

      minimum_accepted_scopes ["public_repo"]

      argument :discussion_id, ID, "The Node ID of the discussion to update.",
        required: true, loads: Objects::Discussion
      argument :title, String, "The new discussion title.", required: false
      argument :body, String, "The new contents of the discussion body.", required: false
      argument :category_id, ID, "The Node ID of a discussion category within the same repository to change this discussion to.",
        required: false, loads: Objects::DiscussionCategory

      field :discussion, Objects::Discussion, "The modified discussion.", null: true
      error_fields

      extras [:execution_errors]

      PATH_TRANSLATIONS = {
        category: "categoryId",
      }.freeze

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :edit_discussion,
            repo: repo,
            current_org: org,
            resource: discussion,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(execution_errors:, discussion:, category: nil, body: nil, title: nil)
        # Set the actor so we can log a Hydro event about this discussion being updated.
        discussion.actor = context[:viewer]

        success = true
        success &&= discussion.update_body(body, context[:viewer], performed_via_integration: context[:integration]) if body
        if success && (title || category)
          discussion.title = title if title
          discussion.category = category if category
          success = discussion.save
        end

        if success
          { discussion: discussion, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(discussion, execution_errors)
          { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(discussion, translate: PATH_TRANSLATIONS) }
        end
      end
    end
  end
end
