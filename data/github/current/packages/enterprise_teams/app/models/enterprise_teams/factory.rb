# typed: strict
# frozen_string_literal: true

module EnterpriseTeams
  class Factory
    sig do
      params(
        enterprise: T.untyped,
        team_name: String,
        sync_to_organizations: T.untyped,
        idp_group_id: T.untyped,
        is_security_manager: T::Boolean
      ).returns(EnterpriseTeam)
    end
    def self.create_enterprise_team(enterprise:, team_name:, sync_to_organizations:, idp_group_id:, is_security_manager:)
      # Create the enterprise team and group mapping (if applicable
      enterprise_team = EnterpriseTeam.new
      enterprise_team_group_mapping = T.let(nil, T.nilable(EnterpriseTeamGroupMapping))

      EnterpriseTeam.transaction do
        enterprise_team.business_id = enterprise.id
        enterprise_team.name = team_name
        if EnterpriseTeam.enabled_for_organizations?(business: enterprise)
          enterprise_team.sync_to_organizations = sync_to_organizations.to_s
        end
        enterprise_team.save!

        # Configure OSM sync if applicable
        EnterpriseTeams::Helper.configure_security_manager_sync(enterprise: enterprise, enterprise_team: enterprise_team, set_security_manager: is_security_manager)

        if idp_group_id.present?
          EnterpriseTeams::Helper.validate_idp_group_enterprise(enterprise, idp_group_id)
          enterprise_team_group_mapping = EnterpriseTeamGroupMapping.new
          enterprise_team_group_mapping.enterprise_team_id = enterprise_team.id
          enterprise_team_group_mapping.external_group_id = idp_group_id
          enterprise_team_group_mapping.save!
        end
      end

      # In the case sync_to_organizations is enabled, we need to generate the mappings + OTs
      EnterpriseTeamOrganizationMappingJob.perform_later(enterprise_team.id) if enterprise_team.sync_to_organizations? && EnterpriseTeam.enabled_for_organizations?(business: enterprise)
      enterprise_team
    end

    sig { params(enterprise: Business, team_name: String, description: String, organization_selection_type: Symbol).returns(BusinessTeam) }
    def self.create_business_team(enterprise:, team_name:, description:, organization_selection_type: :selected_orgs)
      business_team = BusinessTeam.new
      business_team.name = team_name
      business_team.business_id = enterprise.id
      business_team.description = description
      business_team.organization_selection_type = organization_selection_type

      business_team.save!
      business_team
    end
  end
end
