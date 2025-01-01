# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateTeam < Platform::Mutations::Base
      description "Creates a new team."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :organization_id, ID, "The organization ID to create the team under.", required: true, loads: Objects::Organization
      argument :name, String, "The name of the team.", required: true
      argument :description, String, "The description of the team.", required: false
      argument :privacy, Enums::TeamPrivacy, "The level of privacy the team has.", required: true
      argument :notification_setting, Enums::TeamNotificationSetting, "The notification setting that the team has set.", required: false, default_value: "notifications_enabled"
      argument :parent_team_id, ID, "The parent team ID.", required: false, loads: Objects::Team
      argument :ldap_dn, String, "String for LDAP distinguished name.", required: false, camelize: false
      argument :permission, Enums::LegacyTeamPermission, Enums::LegacyTeamPermission.description, visibility: :internal, required: false
      argument :repositories, [String, null: true], "A list of repository full names (e.g., \"organization-name/repository-name\") to add to the team.", visibility: :internal, required: false
      argument :maintainers, [String, null: true], "A list of organization member logins to add as maintainers of the team.", visibility: :internal, required: false
      argument :group_mappings, [Inputs::GroupMapping, null: true], "A list of external groups to map the team to.", required: false, visibility: :under_development

      field :team, Objects::Team, "The new team.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        permission.access_allowed?(:v4_create_team, organization: organization, org: organization, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(organization:, **inputs)

        unless organization.can_create_team?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to create teams on this organization.")
        end

        parent_team_id = inputs[:parent_team] ? inputs[:parent_team].id : nil

        attributes = {}
        attributes[:name] = inputs[:name]
        attributes[:description] = inputs[:description]
        attributes[:privacy] = inputs[:privacy]
        attributes[:notification_setting] = inputs[:notification_setting]
        attributes[:parent_team_id] = parent_team_id
        attributes[:permission] = inputs[:permission].downcase if inputs[:permission]

        group_mappings = Array(inputs[:group_mappings]).map { |group_mapping| group_mapping.to_h }

        repos = organization
          .repositories
          .where(name: validated_repo_names(inputs[:repositories], organization))
          .distinct

        if Array(inputs[:maintainers]).any?
          specified_maintainer_logins = Set.new(inputs[:maintainers].map(&:downcase))
          maintainers = organization.members.where(display_login: specified_maintainer_logins.to_a, business_id: organization.business_id)

          # Logins of maintainers who were specified but aren't valid (either
          # because they aren't org members or because they aren't in the database
          # at all)
          invalid_maintainer_logins = specified_maintainer_logins - maintainers.map(&:display_login).map(&:downcase)

          if invalid_maintainer_logins.present?
            raise Errors::Unprocessable.new("Invalid maintainers were specified.")
          end
        else
          maintainers = []
        end

        team = organization.create_team(creator: context[:viewer], ldap_dn: inputs[:ldap_dn], repos: repos, maintainers: maintainers, group_mappings: group_mappings, attrs: attributes)

        if team.errors.empty?
          { team: team }
        else
          raise Errors::Unprocessable.new(team.errors.full_messages.join(", "))
        end
      end

      private

      # Internal: given a list of NWOs and the new team's organization, validate
      # that the "owner" part of the NWO matches the organization's login. This
      # serves to filter out any tomfoolery where a user could try to gain
      # access to org-owned repos while specifying a repo they own with the same
      # name.
      #
      # Importantly, we choose to silently drop offending NWOs instead of
      # raising since we do not want to confirm/deny the existence of any
      # private repos.
      #
      # Returns an Array<String> of the repo names
      def validated_repo_names(nwos, organization)
        Array(nwos)
          .compact
          .map    { |name_with_owner| name_with_owner.split("/") }
          .filter { |owner, _name| owner == organization.display_login }
          .map    { |_owner, name| name }
      end
    end
  end
end
