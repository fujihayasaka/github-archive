# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class IndirectAssignmentSource < T::Struct
      const :team_name, String
      const :team_url, String
      const :type, String

      sig do
        params(team: T.any(BusinessTeam, Team), owner: T.any(Business, Organization))
        .returns(RoleAssignments::Types::IndirectAssignmentSource)
      end
      def self.from_team(team, owner:)
        new(
          team_name: team.name,
          team_url: team_url(team, owner),
          type: team.type,
        )
      end

      sig do
        params(
          name: String,
          slug: String,
          type: String,
          owner: T.any(Business, Organization)
        ).returns(RoleAssignments::Types::IndirectAssignmentSource)
      end
      def self.from_team_details(name:, slug:, type:, owner:)
        team_url = owner.is_a?(Business) ? business_team_url(slug, owner) : org_team_url(slug, owner)
        new(
          team_name: name,
          team_url: team_url,
          type: type,
        )
      end

      sig { params(team: T.any(BusinessTeam, Team), owner: T.any(Business, Organization)).returns(String) }
      def self.team_url(team, owner)
        case team
        when BusinessTeam
          business_team_url(team.slug, T.cast(owner, Business))
        when Team
          org_team_url(team.slug, T.cast(owner, Organization))
        end
      end

      sig { params(team_slug: String, owner: Business).returns(String) }
      def self.business_team_url(team_slug, owner)
        UrlHelpers.enterprise_team_path(slug: owner.slug, team_slug: team_slug)
      end

      sig { params(team_slug: String, owner: Organization).returns(String) }
      def self.org_team_url(team_slug, owner)
        UrlHelpers.team_path(team_slug: team_slug, org: owner)
      end
    end
  end
end
