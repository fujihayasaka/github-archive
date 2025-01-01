# typed: true
# frozen_string_literal: true

class Api::Admin::Ldap < Api::Admin
  # Update LDAP DN mapping for specified user.
  # rubocop:todo GitHub/ControlAccess
  patch "/admin/ldap/user/:user_id/mapping", operation_id: "enterprise-admin/update-ldap-mapping-for-user" do
    deliver_error!(404) unless GitHub.auth.ldap?

    user = find_user!
    data = receive(Hash)
    updated = user.map_ldap_entry(data["ldap_dn"])
    if updated
      deliver :user_hash, user, private: true
    else
      deliver_error 422, errors: user.errors
    end
  end
  # rubocop:enable GitHub/ControlAccess

  # Update LDAP DN mapping for specified team.
  # https://developer.github.com/v3/admin/ldap/teams/#update-mapping
  # rubocop:todo GitHub/ControlAccess
  patch "/admin/ldap/teams/:team_id/mapping", operation_id: "enterprise-admin/update-ldap-mapping-for-team" do
    deliver_error!(404) unless GitHub.ldap_sync_enabled?
    team = find_team!
    data = receive(Hash)

    updated = Team::Editor.update_team(team, ldap_dn: data["ldap_dn"], updater: current_user)
    if updated
      deliver :team_hash, team, {}
    else
      deliver_error 422, errors: team.errors
    end
  end
  # rubocop:enable GitHub/ControlAccess

  # Initiate LDAP sync for specified user.
  # rubocop:todo GitHub/ControlAccess
  post "/admin/ldap/user/:user_id/sync", operation_id: "enterprise-admin/sync-ldap-mapping-for-user" do
    deliver_error!(404) unless GitHub.ldap_sync_enabled?

    user = find_user!
    user.enqueue_sync_job

    deliver_raw({ status: "queued" }, status: 201)
  end
  # rubocop:enable GitHub/ControlAccess

  # Initiate LDAP sync for specified team.
  # https://developer.github.com/v3/admin/ldap/teams/#sync
  # rubocop:todo GitHub/ControlAccess
  post "/admin/ldap/teams/:team_id/sync", operation_id: "enterprise-admin/sync-ldap-mapping-for-team" do
    deliver_error!(404) unless GitHub.ldap_sync_enabled?
    team = find_team!

    team.enqueue_sync_job

    deliver_raw({ status: "queued" }, status: 201)
  end
  # rubocop:enable GitHub/ControlAccess

  def find_team(param_name: :team_id, org_param_name: :org_id)
    @team ||= Team.find_by(id: int_id_param!(key: param_name))
  end
end
