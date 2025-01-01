# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionCategory < Platform::Objects::Base
      description "A category for discussions in a repository."

      scopeless_tokens_as_minimum

      implements_node templates: [[:rdc, :repo_id, :id]], as: "DIC", ready_date: "2021-07-02" do |discussion_category|
        discussion_category.async_repository.then do |repo|
          {
            prefix: :rdc,
            repo_id: repo&.id,
            id: discussion_category.id,
          }
        end
      end

      implements Interfaces::RepositoryNode

      # Internal: Determine whether the viewer can access this object via the API.
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, category)
        permission.async_repo_and_org_owner(category).then do |repo, org|
          # Preloaded async to avoid relation fetch when generating authzd attributes
          repo.async_parent.then do
            permission.access_allowed?(
              :show_discussion_category,
              repo: repo,
              current_org: org,
              resource: category,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              # Allow discussion categories on public repos to be returned even when the current GitHub app isn't
              # installed on the repo.
              approved_integration_required: false,
            )
          end
        end
      end

      # Internal: Determine whether the viewer can see this object.
      # Returns `true`, `false`, or a `Promise` resolving to `true` or `false`.
      def self.async_viewer_can_see?(permission, category)
        category.async_readable_by?(permission.viewer)
      end

      created_at_field
      updated_at_field

      field :name, String, description: "The name of this category.", null: false
      field :description, String, description: "A description of this category.", null: true
      field :emoji, String, description: "An emoji representing this category.", null: false
      field :emoji_html, Scalars::HTML, description: "This category's emoji rendered as HTML.", null: false
      field :is_answerable, Boolean,
        description:
          "Whether or not discussions in this category support choosing an answer " \
          "with the markDiscussionCommentAsAnswer mutation.",
        null: false,
        method: :supports_mark_as_answer?
      field :is_pollable, Boolean,
        description: "Indicates if this category supports discussion polls.",
        method: :supports_polls?,
        required_capabilities: [:mobile_only_schema_mask],
        null: false
      field :slug, String, description: "The slug of this category.", null: false
      field :supports_announcements, Boolean,
        description: "Indicates if this category supports announcements.",
        method: :supports_announcements?,
        required_capabilities: [:mobile_only_schema_mask],
        null: false
      field :template,
        DiscussionTemplate,
        description: "The category's form template.",
        required_capabilities: [:mobile_only_schema_mask],
        null: true,
        method: :async_template
    end
  end
end
