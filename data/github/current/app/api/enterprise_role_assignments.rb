# typed: true
# frozen_string_literal: true

class Api::EnterpriseRoleAssignments < Api::Enterprise::App
  get "/enterprises/:enterprise_id/enterprise-roles/:role_id/teams", operation_id: "enterprise-admin/list-enterprise-role-teams" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    business_team_ids = UserRole
        .select(:actor_id)
        .where(role_id: role.id, target: enterprise, actor_type: "BusinessTeam")
        .pluck(:actor_id)
    paginated_business_teams = paginate_rel(BusinessTeam.where(id: business_team_ids).order(:id))

    GitHub::PrefillAssociations.prefill_associations(
      paginated_business_teams,
      [:business, :external_group_team],
      available_records: [enterprise]
    )

    deliver :business_team_hash, paginated_business_teams, status: 200
  end

  get "/enterprises/:enterprise_id/enterprise-roles/:role_id/users", operation_id: "enterprise-admin/list-enterprise-role-users" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)

    fetcher = RoleAssignments::FetchRoleAssignments.new(target: enterprise, role: role)
    page = params[:page].to_s =~ /\A\d+\z/ && params[:page].to_i >= 1 ? params[:page].to_i : 1
    role_assignments = fetcher.paginate_user_role_assignments_hash(page:)

    deliver :enterprise_user_role_assignment_hash, {
      role_assignments:,
      total_count: fetcher.total_user_role_assignments
    }, status: 200
  end

  put "/enterprises/:enterprise_id/enterprise-roles/users/:username/:role_id", operation_id: "enterprise-admin/assign-enterprise-role-to-user", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)
    user = find_enterprise_user_by_username!(enterprise, params[:username])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.grant_enterprise_role(assignee: user, role: role)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  put "/enterprises/:enterprise_id/enterprise-roles/teams/:team_slug/:role_id", operation_id: "enterprise-admin/assign-team-to-enterprise-role", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)
    team = find_enterprise_team_by_slug!(enterprise: enterprise, slug: params[:team_slug])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.grant_enterprise_role(assignee: team, role: role)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  delete "/enterprises/:enterprise_id/enterprise-roles/teams/:team_slug/:role_id", operation_id: "enterprise-admin/revoke-enterprise-role-team", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)
    team = find_enterprise_team_by_slug!(enterprise: enterprise, slug: params[:team_slug])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.revoke_enterprise_role(assignee: team, role: role)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  delete "/enterprises/:enterprise_id/enterprise-roles/users/:username/:role_id", operation_id: "enterprise-admin/remove-enterprise-user-role-assignment", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    role = find_enterprise_role!(enterprise: enterprise, param_name: :role_id)
    user = find_enterprise_user_by_username!(enterprise, params[:username])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.revoke_enterprise_role(assignee: user, role: role)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  delete "/enterprises/:enterprise_id/enterprise-roles/users/:username", operation_id: "enterprise-admin/remove-all-enterprise-roles-from-user", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    user = find_enterprise_user_by_username!(enterprise, params[:username])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.revoke_all_enterprise_roles(assignee: user)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  delete "/enterprises/:enterprise_id/enterprise-roles/teams/:team_slug", operation_id: "enterprise-admin/revoke-all-enterprise-roles-team", read_from_replicas: true do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise.custom_enterprise_roles_supported?

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_custom_enterprise_role,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    team = find_enterprise_team_by_slug!(enterprise: enterprise, slug: params[:team_slug])

    with_write(clusters: [ApplicationRecord::Mysql1, ApplicationRecord::Iam]) do
      result = enterprise.revoke_all_enterprise_roles(assignee: team)

      deliver_error! 422, message: result.reason if result.failure?

      deliver_empty status: 204
    end
  end

  private

  def find_enterprise_team_by_slug!(enterprise:, slug:)
    team_slug_without_ent_prefix = BusinessTeam.to_model_slug(slug)

    record_or_404(BusinessTeam.find_by(slug: team_slug_without_ent_prefix, business: enterprise))
  end
end
