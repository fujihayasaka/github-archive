# typed: strict
# frozen_string_literal: true

module Api::Serializer::EnterpriseTeamsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  #
  # data - EnterpriseTeam instance
  # options - Hash
  #
  # Returns Hash.
  sig { params(enterprise_team: T.nilable(EnterpriseTeam), options: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def enterprise_team_hash(enterprise_team, options = {})
    return unless enterprise_team

    team_api_path = "/enterprises/#{enterprise_team.business_id}/teams/#{enterprise_team.id}"
    group_id = EnterpriseTeam.includes(:enterprise_team_group_mappings).find(enterprise_team.id).enterprise_team_group_mappings.first&.external_group&.guid

    {
      id: enterprise_team.id,
      name: enterprise_team.name,
      slug: enterprise_team.slug,
      sync_to_organizations: enterprise_team.sync_to_organizations,
      url: url(team_api_path),
      group_id: group_id,
      html_url: "#{GitHub.url}/enterprises/#{T.must(enterprise_team.business).slug}/teams/#{enterprise_team.slug}",
      members_url: url("#{team_api_path}/members{/member}"),
      created_at: time(enterprise_team.created_at),
      updated_at: time(enterprise_team.updated_at),
    }
  end
end
