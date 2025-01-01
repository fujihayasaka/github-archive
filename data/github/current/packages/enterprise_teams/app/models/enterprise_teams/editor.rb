# typed: strict
# frozen_string_literal: true

module EnterpriseTeams
  class Editor
    extend T::Sig

    sig do
      params(
        enterprise: T.untyped,
        team_slug: String,
        team_name: String,
        sync_to_organizations: T.untyped,
        idp_group_id: T.untyped,
        is_security_manager: T::Boolean
      ).returns(EnterpriseTeam)
    end
    def self.update_team(enterprise:, team_slug:, team_name:, sync_to_organizations:, idp_group_id:, is_security_manager:)
      enterprise_team = enterprise.enterprise_teams.active.find_by(slug: team_slug)
      if enterprise_team.present?
        EnterpriseTeam.transaction do
          enterprise_team.name = team_name
          if EnterpriseTeam.enabled_for_organizations?(business: enterprise)
            enterprise_team.sync_to_organizations = sync_to_organizations.to_s
          end
          enterprise_team.save!

          # Configure OSM sync if applicable
          EnterpriseTeams::Helper.configure_security_manager_sync(enterprise: enterprise, enterprise_team: enterprise_team, set_security_manager: is_security_manager)

          # Setting an IdP group mapping
          if idp_group_id.present?
            EnterpriseTeams::Helper.validate_idp_group_enterprise(enterprise, idp_group_id)

            # MVP only supports one ETGM at most
            enterprise_team_group_mapping = EnterpriseTeamGroupMapping.where(enterprise_team_id: enterprise_team.id).first_or_initialize
            enterprise_team_group_mapping.enterprise_team_id = enterprise_team.id
            enterprise_team_group_mapping.external_group_id = idp_group_id
            enterprise_team_group_mapping.deleted_at = nil
            enterprise_team_group_mapping.save!
          # Removing IdP group mappings if they exist
          elsif idp_group_id.blank?
            # MVP only supports one ETGM at most
            enterprise_team_group_mapping = EnterpriseTeamGroupMapping.where(enterprise_team_id: enterprise_team.id).first
            if enterprise_team_group_mapping
              enterprise_team_group_mapping.update!(deleted_at: Time.current)
            end
          end
        end
      else
        raise ActiveRecord::RecordNotFound
      end

      # In the case the IdP group was updated, we need to re-sync the team members
      ClearEnterpriseTeamMembershipsJob.enqueue(enterprise_team) if idp_group_id.present?

      # In the case sync_to_organizations is updated, we need to generate the mappings + OTs or clear them
      if EnterpriseTeam.enabled_for_organizations?(business: enterprise)
        EnterpriseTeamOrganizationMappingJob.perform_later(enterprise_team.id)
      end

      enterprise_team
    end
  end
end
