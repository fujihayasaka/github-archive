# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SocialAccount < Platform::Objects::Base
      description "Social media profile associated with a user."

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user)
        public_resource = Platform::PublicResource.new(resource: user)
        permission.access_allowed?(
          :read_user_public,
          resource: public_resource,
          current_repo: nil,
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :url, Scalars::URI, null: false,
        description: "URL of the social media account."

      field :provider, Enums::SocialAccountProvider, null: false,
        description: "Software or company that hosts the social media account.",
        method: :key

      field :display_name, String, null: false,
        description: "Name of the social media account as it appears on the profile.",
        method: :format_account_name

      field :icon_url, Scalars::URI, null: true,
        description: "URL of the appropriate icon to use for this social media account. " \
          "May be null if an octicon is used instead.",
        mobile_only: true

      def icon_url
        if icon_subpath = @object.svg_path
          [GitHub.asset_host_url.presence || GitHub.url, "images/modules", "#{icon_subpath}.svg"].join("/")
        end
      end

      field :octicon, String, null: true,
        description: "Name of the octicon to use for this social media account. " \
          "May be null if an iconURL is used instead.",
        method: :octicon_name,
        mobile_only: true
    end
  end
end
