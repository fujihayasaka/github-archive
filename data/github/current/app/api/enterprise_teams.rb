# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeams < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi

  sig { returns(T::Hash[Symbol, String]) }
  def base_error_config
    if GitHub.flipper[:use_et_early_access_documentation_url].enabled?
      { documentation_url: "https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/articles/rest-api-endpoints-for-enterprise-teams" }
    else
      {}
    end
  end

  post "/enterprises/:enterprise_id/teams", operation_id: "enterprise-teams/create" do
    enterprise = find_enterprise!(error_options: base_error_config)
    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled?

    control_access :manage_enterprise_teams,
    resource: enterprise,
    allow_integrations: false,
    allow_user_via_granular_actor: false

    # Prevent creating more than one ET in GHES environment
    if GitHub.esm_enabled? && enterprise.enterprise_teams.exists?
      deliver_error! 403, **base_error_config, message: "A maximum of one enterprise team can be created"
    end

    data = receive(Hash)

    # Build team params
    name = data.fetch("name", "")

    # TODO update the early access docs to remove this completely, we can't set up org sync without ESM in the UI
    sync_to_organizations = data.fetch("sync_to_organizations", "disabled")
    if sync_to_organizations == "all"
      if enterprise.seats_plan_basic?
        deliver_error! 403, **base_error_config, message: "Organizations are not enabled for this enterprise."
      else
        deliver_error! 403, **base_error_config, message: "Organizations sync is not supported via API."
      end
    end

    idp_group_guid = enterprise.enterprise_managed? ? data.fetch("group_id", nil) : nil
    if idp_group_guid
      idp_group_id = ExternalGroup.find_by(guid: idp_group_guid)&.id
      deliver_error! 404, message: "Unable to find IdP group with id: #{idp_group_guid}" if idp_group_id.nil?
    end

    enterprise_team = EnterpriseTeams::Factory.create_enterprise_team(
      enterprise: enterprise,
      team_name: name,
      sync_to_organizations: sync_to_organizations.to_s,
      idp_group_id: idp_group_id,
      is_security_manager: false)

    deliver :enterprise_team_hash, enterprise_team, status: 201
  rescue ActiveRecord::RecordInvalid => e
    deliver_error! 422, **base_error_config, message: e.record.errors
  end

  # list teams in :enterprise_id
  get "/enterprises/:enterprise_id/teams", operation_id: "enterprise-teams/list" do
    enterprise = find_enterprise!(error_options: base_error_config)

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled?

    control_access :read_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    enterprise_teams_list = enterprise.enterprise_teams.includes(:enterprise_team_assignments).active.order(:id)

    teams = paginate_rel(enterprise_teams_list)

    deliver :enterprise_team_hash, teams, status: 200
  end

  get "/enterprises/:enterprise_id/teams/:team_id", operation_id: "enterprise-teams/get" do
    enterprise = find_enterprise!(error_options: base_error_config)
    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled?

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = record_or_404(
      enterprise.enterprise_teams.find_by(slug: params[:team_slug]) ||
      enterprise.enterprise_teams.find_by(id: params[:team_id]),
      error_options: base_error_config
    )

    deliver :enterprise_team_hash, team, status: 200
  end

  # delete a team in :enterprise_id
  delete "/enterprises/:enterprise_id/teams/:team_id", operation_id: "enterprise-teams/delete" do
    team = find_enterprise_team!(error_options: base_error_config)
    enterprise = team.business

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled?
    deliver_error! 404, **base_error_config if GitHub.esm_enabled?

    set_forbidden_message "You must be an enterprise owner to remove an enterprise team"
    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team.destroy!

    deliver_empty status: 204
  end

  # update a team in :enterprise_id
  patch "/enterprises/:enterprise_id/teams/:team_id", operation_id: "enterprise-teams/update" do
    team = find_enterprise_team!(error_options: base_error_config)
    enterprise = team.business
    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled?

    set_forbidden_message "You must be an enterprise owner to update an enterprise team"
    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    # Parse the request body
    data = receive(Hash)
    name = data.fetch("name", team.name)

    # TODO update the early access docs to remove this completely, we can't set up org sync without ESM in the UI
    sync_to_organizations = data.fetch("sync_to_organizations", team.sync_to_organizations)
    if sync_to_organizations == "all" && enterprise.seats_plan_basic?
      deliver_error! 403, **base_error_config, message: "Organizations are not enabled for this enterprise."
    elsif team.sync_to_organizations == "all" && sync_to_organizations == "disabled"
      deliver_error! 403, **base_error_config, message: "Disabling organizations sync is not allowed"
    elsif team.sync_to_organizations == "disabled" && sync_to_organizations == "all"
      deliver_error! 403, **base_error_config, message: "Organizations sync is not supported via API."
    end

    if enterprise.enterprise_managed?
      group_guid_provided = data.key?("group_id")
      group_guid = data["group_id"]

      group_id = if group_guid_provided && group_guid.nil?
        # Set group_id to nil if it was explicitly set to nil
        nil
      elsif group_guid_provided
        group = ExternalGroup.find_by(guid: group_guid)
        deliver_error! 404, message: "Unable to find IdP group with id: #{group_guid}" if group.nil?
        group.id
      else
        # default to the existing group id if no group_id was provided
        team.enterprise_team_group_mappings.first&.external_group_id
      end
    end

    # For is_security_manager: it was hardcoded to false in the past because not supported.
    # But the side effect is that updating another field was disabling ESM.
    # Since we don't allow updating ESM and org sync separately and now also block disabling ESM, make sure the value doesn't change.
    # TODO since we have removed old check boxes and security center is now managing ESM toggle with org sync,
    # we should clean up the editor code from any reference to org-sync/esm and leave it untouched
    # (and clean up the back and forth payload exchange between editor UI and web controller just to to avoid changing the values).
    EnterpriseTeams::Editor.update_team(
      enterprise: enterprise,
      team_slug: team.slug,
      team_name: name,
      sync_to_organizations: sync_to_organizations.to_s,
      idp_group_id: group_id,
      is_security_manager: team.sync_to_organizations == "all"
    )
    deliver :enterprise_team_hash, team.reload, status: 200
  rescue ActiveRecord::RecordInvalid => e
    deliver_error! 422, **base_error_config, message: e.record.errors
  end
end
