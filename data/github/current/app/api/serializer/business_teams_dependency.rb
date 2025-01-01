# typed: true
# frozen_string_literal: true

module Api::Serializer::BusinessTeamsDependency
  extend T::Helpers
  include Api::Serializer::OrganizationsDependency

  requires_ancestor { Api::Serializer }
  # Creates a Hash to be serialized to JSON for business teams.
  # Updates the Hash with the latest created_at and updated_at timestamps.
  #
  # business_team - BusinessTeam instance
  #
  # options       - Hash
  #
  # Returns a Hash if the business team exists, or nil.
  def business_team_hash(business_team, options = {})
    return unless business_team

    # Gets the base hash from the parent method
    hash = team_simple_hash(business_team, options)

    # Removes organization-specific fields that do not apply to business teams
    [:repositories_url, :permission, :notification_setting, :privacy, :node_id].each { |k| hash.delete(k) }

    # Creates a BusinessTeam API path because the base hash does not contain organization_id or repositories_url
    business_team_api_path = "/enterprises/#{business_team.business_id}/teams/#{business_team.id}"

    # Overrides relevant fields for business teams
    hash.update \
      url: url(business_team_api_path),
      members_url: url("#{business_team_api_path}/members{/member}"),
      created_at: time(business_team.created_at),
      updated_at: time(business_team.updated_at)

    if business_team.business.erp_feature_enabled?(:enterprise_teams_org_assignment)
      hash.update \
        organization_selection_type: business_team.organization_selection_type.to_s
    end

    hash
  end
end
