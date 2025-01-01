# typed: true
# frozen_string_literal: true

module Api::Serializer::TeamsDependency
  extend T::Helpers
  include Api::Serializer::RepositoriesDependency

  requires_ancestor { Api::Serializer }

  # Internal: a method to build a hash that matches the team-simple schema. The
  # idea here is that you could compose more complex team representations using
  # this method to give you a base to work from.
  #
  # Returns Hash
  private def team_simple_hash(team, options = {})
    return unless team

    team_api_path = "/organizations/#{team.organization_id}/team/#{team.id}"
    hash = {
      name: team.name,
      id: team.id,
      node_id: global_id_for(team, options),
      slug: team.to_param,
      description: team.description,
      privacy: team.privacy.to_s,
      notification_setting: team.notification_setting.to_s,
      url: url(team_api_path),
      html_url: team.permalink,
      members_url: url("#{team_api_path}/members{/member}"),
      repositories_url: url("#{team_api_path}/repos"),
    }

    if team.feature_flag_enabled?(:team_type_field_rollout, default: false)
      case team
      when BusinessTeam
        hash[:type] = "enterprise"
        hash[:enterprise_id] = team.business_id
      else
        hash[:type] = "organization"
        hash[:organization_id] = team.organization_id
      end
    end

    if repo = options[:repo]

      team_permission = team.async_most_capable_action_or_role_for(repo, include_custom_roles: true, role_priority: true).sync
      team_permission = Team::ABILITIES_TO_PERMISSIONS[team_permission] if Team::ABILITIES_TO_PERMISSIONS.key?(team_permission)
      hash[:permission] = team_permission
      hash[:permissions] = permissions_hash(repo, actor: team)
    else
      hash[:permission] = team.permission.blank? ? "pull" : team.permission
    end

    hash
  end
end
