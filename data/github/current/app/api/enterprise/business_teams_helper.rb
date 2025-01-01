# typed: true
# frozen_string_literal: true

module Api::Enterprise::BusinessTeamsHelper
  extend T::Helpers

  requires_ancestor { Api::EnterpriseTeams }

  sig { params(enterprise: Business).returns(String) }
  def list_business_teams(enterprise:)
    teams_list = enterprise.business_teams.order(:id)
    teams = paginate_rel(teams_list)

    deliver :business_team_hash, teams, status: 200
  end

  sig { params(error_options: Hash).returns(String) }
  def get_business_team!(error_options)
    business_team = find_business_team!(error_options: error_options)

    deliver :business_team_hash, business_team, status: 200
  end

  sig { params(enterprise: Business).returns(String) }
  def create_business_team!(enterprise)
    data = receive(Hash)

    name = data.fetch("name", "")
    description = data.fetch("description", "")
    external_group_id = enterprise.erp_feature_enabled?(:enterprise_teams_members_management) ? data.fetch("group_id", nil) : nil
    org_selection = enterprise.erp_feature_enabled?(:enterprise_teams_org_assignment) ? data.fetch("organization_selection_type", "disabled") : "disabled"
    business_team = EnterpriseTeams::Factory.create_business_team(enterprise: enterprise, team_name: name, description: description, organization_selection_type: org_selection.to_sym, external_group_id: external_group_id)
    deliver :business_team_hash, business_team, status: 201
  rescue EnterpriseTeams::Factory::BusinessTeamValidationError => e
    deliver_error! 422, **base_error_config, message: e.message
  end

  # Delete a business team
  #
  # @param enterprise [Business] The enterprise
  # @return [void]
  sig { params(enterprise: Business).void }
  def delete_business_team(enterprise:)
    team = find_business_team!(error_options: base_error_config)

    # Delete the team
    team.destroy!

    # Deliver empty response with 204 status
    deliver_empty status: 204
  end

  sig { void }
  def update_business_team; end
end
