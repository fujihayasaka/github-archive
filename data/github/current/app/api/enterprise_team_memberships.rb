# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeamMemberships < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi
  include Api::Enterprise::BusinessTeamMembershipHelpers

  sig { returns(T::Hash[Symbol, String]) }
  def base_error_config
    { documentation_url: "https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/articles/rest-api-endpoints-for-enterprise-teams" }
  end

  get "/enterprises/:enterprise_id/teams/:team_id/memberships", operation_id: "enterprise-team-memberships/list" do
    enterprise = find_enterprise!(error_options: base_error_config)
    erp_feature_enabled = BusinessTeam.enabled_for_enterprise?(business: enterprise)

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled? || erp_feature_enabled

    control_access :read_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if erp_feature_enabled
      list_business_team_memberships(enterprise)
    else
      enterprise_team = find_enterprise_team!(error_options: base_error_config)
      business_members = EnterpriseTeams::Helper.filtered_members(current_user, enterprise_team)

      if GitHub.single_business_environment?
        team_members = paginate_rel(business_members)
      else
        paginated_business_members = paginate_rel(business_members)
        team_members = WillPaginate::Collection.create(
          paginated_business_members.current_page,
          paginated_business_members.per_page,
          paginated_business_members.total_entries
        ) do |pager|
          pager.replace paginated_business_members.includes(:user).map(&:user)
        end
      end

      deliver :user_hash, team_members, status: 200
    end
  end

  get "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/get" do
    enterprise = find_enterprise!(error_options: base_error_config)
    erp_feature_enabled = BusinessTeam.enabled_for_enterprise?(business: enterprise)

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled? || erp_feature_enabled

    control_access :read_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if erp_feature_enabled
      get_business_team_membership!(enterprise)
    else
      enterprise_team = find_enterprise_team!(error_options: base_error_config)
      user = validate_user!(enterprise_team.business, params[:username])

      deliver_error! 404, **base_error_config unless enterprise_team.member?(user)
      deliver :user_hash, user, status: 200
    end
  end

  delete "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/remove" do
    enterprise = find_enterprise!(error_options: base_error_config)
    erp_feature_enabled = BusinessTeam.enabled_for_enterprise?(business: enterprise)

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled? || erp_feature_enabled

    set_forbidden_message "You must be an enterprise owner to remove a user from an enterprise team"
    control_access :manage_enterprise_teams,
    resource: enterprise,
    allow_integrations: false,
    allow_user_via_granular_actor: false

    if erp_feature_enabled
      delete_business_team_membership!(enterprise: enterprise, username: params[:username])
    else
      enterprise_team = find_enterprise_team!(error_options: base_error_config)
      deliver_error! 422, **base_error_config, message: "Unable to remove member from a team managed by an external group." unless enterprise_team.direct_memberships_enabled?

      user = validate_user!(enterprise, params[:username])

      membership = record_or_404(enterprise_team.enterprise_team_memberships.find_by(user: user), error_options: base_error_config)
      begin
        membership.destroy!
      rescue ActiveRecord::RecordNotDestroyed
        deliver_error! 422, **base_error_config, message: "Unable to remove member from the team."
      end

      deliver_empty status: 204
    end
  end

  put "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/add" do
    enterprise = find_enterprise!(error_options: base_error_config)
    erp_feature_enabled = BusinessTeam.enabled_for_enterprise?(business: enterprise)

    deliver_error! 404, **base_error_config unless enterprise.enterprise_teams_enabled? || erp_feature_enabled

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if erp_feature_enabled
      create_business_team_membership!(enterprise)
    else
      enterprise_team = find_enterprise_team!
      deliver_error! 422, **base_error_config, message: "Unable to add member to a team managed by an external group." unless enterprise_team.direct_memberships_enabled?

      user = validate_user!(enterprise_team.business, params[:username])
      create_membership!(enterprise_team, user)

      deliver :user_hash, user, status: 201
    end
  end

  post "/enterprises/:enterprise_id/teams/:team_id/memberships/add", operation_id: "enterprise-team-memberships/bulk-add", read_from_replicas: true do
    enterprise = find_enterprise!(error_options: base_error_config)
    deliver_error! 404, **base_error_config unless BusinessTeam.enabled_for_enterprise?(business: enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    bulk_create_business_team_memberships!(enterprise)
  end

  post "/enterprises/:enterprise_id/teams/:team_id/memberships/remove", operation_id: "enterprise-team-memberships/bulk-remove", read_from_replicas: true do
    enterprise = find_enterprise!(error_options: base_error_config)
    deliver_error! 404, **base_error_config unless BusinessTeam.enabled_for_enterprise?(business: enterprise)

    control_access :manage_enterprise_teams,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    # All reads/writes from primaries that aren't wrapped in a `with_write` block are not allowed
    # https://github.com/github/api-platform/blob/master/playbooks/api-read-from-replicas-adoption-guide.md#step-3-wrap-write-operations-using-with_write
    with_write do
      bulk_delete_business_team_memberships!(enterprise)
    end
  end

  # This method validates a user within a given business context. THe user must exist and be in the business.
  # If the user validation fails, it handles the error and sends an appropriate HTTP response.
  sig { params(business: Business, username: String).returns(User) }
  def validate_user!(business, username)
    begin
      EnterpriseTeams::Helper.validate_user_parameter(business, username)
    rescue ArgumentError => e
      deliver_error! 400, **base_error_config, message: e.message
    rescue EnterpriseTeams::Helper::UserNotInEnterpriseError => e
      deliver_error! 404, **base_error_config, message: e.message
    end
  end

  # This method attempts to create a membership for a user in an enterprise team.
  # If the membership creation fails, it handles the error and sends an appropriate HTTP response.
  sig { params(enterprise_team: EnterpriseTeam, user: User).void }
  def create_membership!(enterprise_team, user)
    begin
      EnterpriseTeams::Helper.create_team_membership(enterprise_team, user)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 400, **base_error_config, message: e.message
    rescue ActiveRecord::RecordNotUnique
      deliver_error! 400, **base_error_config, message: "This user is already part of the enterprise team"
    end
  end
end
