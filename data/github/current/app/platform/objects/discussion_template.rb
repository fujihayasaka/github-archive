# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionTemplate < Platform::Objects::Base
      mobile_only true
      description "A discussion category form template."

      scopeless_tokens_as_minimum

      # A DiscussionTemplate is only accessible via its parent DiscussionCategory object.
      # Its permissions are handled on the DiscussionCategory object itself.
      def self.async_api_can_access?(permission, discussion_template)
        permission.async_repo_and_org_owner(discussion_template.category).then do |repo, org|
          # Preloaded async to avoid relation fetch when generating authzd attributes
          repo.async_parent.then do
            permission.access_allowed?(
              :show_discussion_category,
              repo: repo,
              current_org: org,
              resource: discussion_template.category,
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
        discussion_template.category.async_readable_by?(permission.viewer)
      end

      field :url, Scalars::URI, "The URL to access the new discussion form using the template.", null: false
    end
  end
end
