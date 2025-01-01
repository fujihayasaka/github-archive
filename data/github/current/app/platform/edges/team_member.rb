# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class TeamMember < Edges::Base

      include Scientist

      description "Represents a user who is a member of a team."

      minimum_accepted_scopes ["read:org"]

      field :node, Objects::User, null: false

      url_fields prefix: :member_access, description: "The HTTP URL to the organization's member access page." do |edge|
        member = edge.node
        team = edge.parent
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/people/{person}")
          template.expand org: org.display_login, person: member.display_login
        end
      end

      field :role, Enums::TeamMemberRole, description: "The role the member has on the team.", null: false

      def role
        user = @object.node
        team = @object.parent
        Platform::Loaders::Authorization::MostCapableUserRoleOnTeam.load(user: user, team: team)
      end
    end
  end
end
