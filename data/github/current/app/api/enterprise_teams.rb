# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeams < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi
  extend T::Sig

  sig { returns(T::Hash[Symbol, String]) }
  def missing_repository_options # This is a confusing name. It overrides the default API return values in Api::App and was defined a long time ago. The name also doesn't make sense where it's used in FindersDependency, but it's what we're stuck with.
    { documentation_url: "https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/articles/rest-api-endpoints-for-enterprise-teams" }
  end

  post "/enterprises/:enterprise_id/teams", operation_id: "enterprise-teams/create" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.enterprise_teams_enabled?

    control_access :manage_enterprise_teams,
    resource: enterprise,
    allow_integrations: false,
    allow_user_via_granular_actor: false

    # Prevent creating more than one ET in GHES environment
    if GitHub.esm_enabled? && enterprise.enterprise_teams.exists?
      deliver_error! 403, message: "A maximum of one enterprise team can be created"
    end

    data = receive(Hash)

    # Build team params
    name = data.fetch("name", "")

    # TODO update the early access docs to remove this completely, we can't set up org sync without ESM in the UI
    sync_to_organizations = data.fetch("sync_to_organizations", "disabled")
    if sync_to_organizations == "all"
      if enterprise.seats_plan_basic?
        deliver_error! 403, message: "Organizations are not enabled for this enterprise."
      else
        deliver_error! 403, message: "Organizations sync is not supported via API."
      end
    end

    idp_group_id = enterprise.enterprise_managed? ? data.fetch("group_id", nil) : nil

    enterprise_team = EnterpriseTeams::Factory.create_enterprise_team(
      enterprise: enterprise,
      team_name: name,
      sync_to_organizations: sync_to_organizations.to_s,
      idp_group_id: idp_group_id,
      is_security_manager: false)

    deliver :enterprise_team_hash, enterprise_team, status: 201
  rescue ActiveRecord::RecordInvalid => e
    deliver_error! 422, message: e.record.errors
  end

  # list teams in :enterprise_id
  get "/enterprises/:enterprise_id/teams", operation_id: "enterprise-teams/list" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.enterprise_teams_enabled?

    control_access :read_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    enterprise_teams_list = enterprise.enterprise_teams.includes(:enterprise_team_assignments).active.order(:id)

    teams = paginate_rel(enterprise_teams_list)

    deliver :enterprise_team_hash, teams, status: 200
  end

  get "/enterprises/:enterprise_id/teams/:team_id", operation_id: "enterprise-teams/get" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.enterprise_teams_enabled?

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    team = record_or_404(
      enterprise.enterprise_teams.find_by(slug: params[:team_slug]) ||
      enterprise.enterprise_teams.find_by(id: params[:team_id])
    )

    deliver :enterprise_team_hash, team, status: 200
  end

  # delete a team in :enterprise_id
  delete "/enterprises/:enterprise_id/teams/:team_id", operation_id: "enterprise-teams/delete" do
    team = find_enterprise_team!
    enterprise = team.business

    deliver_error! 404 unless enterprise.enterprise_teams_enabled?
    deliver_error! 404 if GitHub.esm_enabled?

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
    team = find_enterprise_team!
    enterprise = team.business
    deliver_error! 404 unless enterprise.enterprise_teams_enabled?

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
      deliver_error! 403, message: "Organizations are not enabled for this enterprise."
    elsif team.sync_to_organizations == "all" && sync_to_organizations == "disabled"
      deliver_error! 403, message: "Disabling organizations sync is not allowed"
    elsif team.sync_to_organizations == "disabled" && sync_to_organizations == "all"
      deliver_error! 403, message: "Organizations sync is not supported via API."
    end
    group_id = enterprise.enterprise_managed? ? data.fetch("group_id", team.enterprise_team_group_mappings.first&.external_group_id) : nil

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
    deliver_error! 422, message: e.record.errors
  end
end
