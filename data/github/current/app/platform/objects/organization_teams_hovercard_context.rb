# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationTeamsHovercardContext < Objects::Base
      description "An organization teams hovercard context"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ctx)
        # We always return true here because this object only returns 3 fields:
        # URL for the full team list for this user - this does not require any permissions (you can handcraft the URL since you already know the org and user name)
        # Total team count and relevant_teams - Both already have a permission check in app/platform/objects/team.rb. There's no need to duplicate this check here since no edges will be returned if the user doesn't have access to the teams.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # We always return true here for the same reasons as above
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      implements Interfaces::HovercardContext

      url_fields prefix: :teams, description: "The URL for the full team list for this user" do |hovercard_context|
        template = Addressable::Template.new("/orgs/{org}/teams?query=@{user}")
        template.expand(user: hovercard_context.user.display_login, org: hovercard_context.organization.display_login)
      end

      field :total_team_count, Integer, null: false do
        description "The total number of teams the user is on in the organization"
      end

      field :relevant_teams, Connections.define(Objects::Team), connection: true, null: false, method: :highlighted do
        description "Teams in this organization the user is a member of that are relevant"
      end
    end
  end
end
