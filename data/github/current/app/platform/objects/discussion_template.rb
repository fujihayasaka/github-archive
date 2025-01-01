# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionTemplate < Platform::Objects::Base
      required_capabilities [:mobile_only_schema_mask]
      description "A discussion category form template."

      scopeless_tokens_as_minimum

      # A DiscussionTemplate is only accessible via its parent DiscussionCategory object.
      # Its permissions are handled on the DiscussionCategory object itself.
      def self.async_api_can_access?(permission, discussion_template)
        category = discussion_template.category
        return Promise.resolve(false) unless category

        permission.async_repo_and_org_owner(category).then do |repo, org|
          next false unless repo

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

      # A DiscussionTemplate is only accessible via its parent DiscussionCategory object.
      # Its permissions are handled on the DiscussionCategory object itself.
      def self.async_viewer_can_see?(permission, discussion_template)
        category = discussion_template.category
        return Promise.resolve(false) unless category

        category.async_readable_by?(permission.viewer)
      end

      field :url, Scalars::URI, "The URL to access the new discussion form using the template.", null: false
    end
  end
end
