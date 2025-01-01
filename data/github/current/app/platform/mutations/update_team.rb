# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeam < Platform::Mutations::Base
      description "Updates an existing team."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :team_id, ID, "The Team ID to update.", required: true, loads: Objects::Team
      argument :name, String, "The name of team.", required: false
      argument :description, String, "The description of team.", required: false
      argument :privacy, Enums::TeamPrivacy, "The level of privacy the team has.", required: false
      argument :notification_setting, Enums::TeamNotificationSetting, "The notification setting that the team has set.", required: false
      argument :parent_team_id, ID, "The parent team ID.", required: false, loads: Objects::Team
      argument :ldap_dn, String, "String for LDAP distinguished name.", required: false, camelize: false
      argument :permission, Enums::LegacyTeamPermission, Enums::LegacyTeamPermission.description, visibility: :internal, required: false
      argument :group_mappings, [Inputs::GroupMapping, null: true], "A list of external groups to map the team to.", required: false, visibility: :under_development

      field :team, Objects::Team, "The updated team.", null: true

      def resolve(team:, **inputs)
        actor = context[:actor]
        viewer = context[:viewer]

        # Attributes updated if necessary
        attributes = {}
        attributes[:name] = inputs[:name] if inputs[:name]
        attributes[:description] = inputs[:description] if inputs[:description]
        attributes[:ldap_dn] = inputs[:ldap_dn] if inputs[:ldap_dn]
        attributes[:updater] = actor
        attributes[:permission] = inputs[:permission].downcase if inputs[:permission]
        attributes[:privacy] = inputs[:privacy] if inputs[:privacy]
        attributes[:notification_setting] = inputs[:notification_setting] if inputs[:notification_setting]

        unless team.updatable_by?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this team.")
        end

        success, error = team.request_update_on_behalf_of(actor,
          attributes,
          inputs.slice(:parent_team),
          group_mappings: inputs[:group_mappings])

        if success
          { team: team }
        elsif error[:team_validation]
          raise Errors::Validation.new(error[:message])
        else
          raise Errors::Unprocessable.new(error[:message])
        end
      end
    end
  end
end
