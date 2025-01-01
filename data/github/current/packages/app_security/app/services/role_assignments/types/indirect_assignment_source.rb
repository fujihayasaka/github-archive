# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class IndirectAssignmentSource < T::Struct
      const :team_name, String
      const :team_url, String
      const :type, String

      sig do
        params(team: T.any(BusinessTeam, Team), owner: T.any(Business, Organization), stafftools: T::Boolean)
        .returns(RoleAssignments::Types::IndirectAssignmentSource)
      end
      def self.from_team(team, owner:, stafftools: false)
        new(
          team_name: team.name,
          team_url: team_url(team.id, team.slug, owner, stafftools),
          type: team.type,
        )
      end

      sig do
        params(
          id: Integer,
          name: String,
          slug: String,
          type: String,
          owner: T.any(Business, Organization),
          stafftools: T::Boolean,
        ).returns(RoleAssignments::Types::IndirectAssignmentSource)
      end
      def self.from_team_details(id:, name:, slug:, type:, owner:, stafftools: false)
        new(
          team_name: name,
          team_url: team_url(id, slug, owner, stafftools),
          type: type,
        )
      end

      sig { params(team_id: Integer, team_slug: String, owner: T.any(Business, Organization), stafftools: T::Boolean).returns(String) }
      def self.team_url(team_id, team_slug, owner, stafftools)
        case owner
        when Business
          if stafftools
            stafftools_enterprise_teams_path(team_id, owner)
          else
            business_team_url(team_slug, owner)
          end
        when Organization
          if stafftools
            stafftools_org_team_url(team_slug, owner)
          else
            org_team_url(team_slug, owner)
          end
        end
      end

      sig { params(team_slug: String, owner: Business).returns(String) }
      def self.business_team_url(team_slug, owner)
        UrlHelpers.enterprise_team_path(slug: owner.slug, team_slug: team_slug)
      end

      sig { params(team_id: Integer, owner: Business).returns(String) }
      def self.stafftools_enterprise_teams_path(team_id, owner)
        UrlHelpers.stafftools_enterprise_team_path(owner, team_id)
      end

      sig { params(team_slug: String, owner: Organization).returns(String) }
      def self.org_team_url(team_slug, owner)
        UrlHelpers.team_path(team_slug: team_slug, org: owner)
      end

      sig { params(team_slug: String, owner: Organization).returns(String) }
      def self.stafftools_org_team_url(team_slug, owner)
        UrlHelpers.stafftools_user_team_path(owner, team_slug)
      end
    end
  end
end
