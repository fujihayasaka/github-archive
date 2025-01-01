# typed: strict
# frozen_string_literal: true

class Api::EnterpriseTeamMemberships < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi
  include Api::Enterprise::BusinessTeamMembershipHelpers

  sig { returns(T::Hash[Symbol, String]) }
  def base_error_config
    { documentation_url: "https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/articles/rest-api-endpoints-for-enterprise-teams" }
  end

  sig { params(enterprise: Business).returns(T::Boolean) }
  def enterprise_teams_v2_enabled?(enterprise)
    BusinessTeam.enabled_for_enterprise?(business: enterprise) && enterprise.feature_enabled?(:enterprise_teams_crud_api)
  end

  get "/enterprises/:enterprise_id/teams/:team_id/memberships", operation_id: "enterprise-team-memberships/list" do
    enterprise_team = find_enterprise_team!
    erp_feature_enabled = enterprise_teams_v2_enabled?(enterprise_team.business)

    deliver_error! 404, **base_error_config unless enterprise_team.business.enterprise_teams_enabled? || erp_feature_enabled

    control_access :read_enterprise_teams,
      resource: enterprise_team.business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

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

  get "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/get" do
    enterprise_team = find_enterprise_team!
    erp_feature_enabled = enterprise_teams_v2_enabled?(enterprise_team.business)

    deliver_error! 404, **base_error_config unless enterprise_team.business.enterprise_teams_enabled? || erp_feature_enabled

    control_access :read_enterprise_teams,
      resource: enterprise_team.business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    user = validate_user!(enterprise_team.business, params[:username])

    deliver_error! 404, **base_error_config unless enterprise_team.member?(user)

    deliver :user_hash, user, status: 200
  end

  delete "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/remove" do
    enterprise_team = find_enterprise_team!
    erp_feature_enabled = enterprise_teams_v2_enabled?(enterprise_team.business)

    deliver_error! 404, **base_error_config unless enterprise_team.business.enterprise_teams_enabled? || erp_feature_enabled

    set_forbidden_message "You must be an enterprise owner to remove a user from an enterprise team"
    control_access :manage_enterprise_teams,
    resource: enterprise_team.business,
    allow_integrations: false,
    allow_user_via_granular_actor: false

    deliver_error! 422, **base_error_config, message: "Unable to remove member from a team managed by an external group." unless enterprise_team.direct_memberships_enabled?

    user = validate_user!(enterprise_team.business, params[:username])
    membership = record_or_404(enterprise_team.enterprise_team_memberships.find_by(user: user), error_options: base_error_config)
    begin
      membership.destroy!
    rescue ActiveRecord::RecordNotDestroyed
      deliver_error! 422, **base_error_config, message: "Unable to remove member from the team."
    end

    deliver_empty status: 204
  end

  put "/enterprises/:enterprise_id/teams/:team_id/memberships/:username", operation_id: "enterprise-team-memberships/add" do
    enterprise_team = find_enterprise_team!
    erp_feature_enabled = enterprise_teams_v2_enabled?(enterprise_team.business)

    deliver_error! 404, **base_error_config unless enterprise_team.business.enterprise_teams_enabled? || erp_feature_enabled

    control_access :manage_enterprise_teams,
      resource: enterprise_team.business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    deliver_error! 422, **base_error_config, message: "Unable to add member to a team managed by an external group." unless enterprise_team.direct_memberships_enabled?

    user = validate_user!(enterprise_team.business, params[:username])
    create_membership!(enterprise_team, user)

    deliver :user_hash, user, status: 201
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
