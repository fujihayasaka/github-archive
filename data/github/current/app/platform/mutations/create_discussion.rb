# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateDiscussion < Platform::Mutations::Base
      description "Create a discussion."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The id of the repository on which to create the discussion.", required: true,
        loads: Objects::Repository, as: :repository

      argument :title, String, "The title of the discussion.", required: true
      argument :body, String, "The body of the discussion.", required: true
      argument :category_id, ID, "The id of the discussion category to associate with this discussion.",
        required: true, loads: Objects::DiscussionCategory

      error_fields
      field :discussion, Objects::Discussion, "The discussion that was just created.", null: true

      extras [:execution_errors]

      PATH_TRANSLATION = {
        category: "categoryId",
      }.freeze

      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          action = if inputs[:category].supports_announcements?
            :create_discussion_announcement
          else
            :create_discussion
          end

          permission.access_allowed?(
            action,
            repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, title:, body:, category:, execution_errors:)
        if category.supports_announcements? && !repository.can_create_discussion_announcements?(context[:viewer])
          raise Errors::Forbidden.new("You do not have permission to create an announcement discussion. Only admins and maintainers can create announcements.")
        end

        discussion = repository.discussions.new(
          repository: repository,
          user: context[:viewer],
          title: title,
          body: body,
          category: category,
        )

        if context[:permission].integration_user_request?
          discussion.performed_via_integration = context[:integration]
        end

        if discussion.save
          # Reload the record to pick up the recomputed total_upvotes field
          { discussion: discussion.reload, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(discussion, execution_errors)
          { discussion: nil, errors: Platform::UserErrors.mutation_errors_for_model(discussion, translate: PATH_TRANSLATION) }
        end
      end
    end
  end
end
