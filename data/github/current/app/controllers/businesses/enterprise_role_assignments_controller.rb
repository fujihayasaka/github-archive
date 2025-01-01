# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseRoleAssignmentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include RoleAssignments::SearchHelper
  include RoleAssignments::AvatarOrgsHelper

  INVALID_ASSIGNEE_ERROR = "Invalid assignee for enterprise role assignment."
  ROLE_ASSIGNMENT_ERRORS = T.let({
    Permissions::Granters::EnterpriseRoleGranter::NOT_A_MEMBER => INVALID_ASSIGNEE_ERROR
  }.freeze, T::Hash[String, String])

  before_action :custom_enterprise_roles_enabled
  before_action :read_enterprise_roles_required, only: [:index]
  before_action :write_enterprise_roles_required, except: [:index]

  layout "layouts/react_business"

  allow_verified_fetch only: [:create, :destroy]

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    only: [:index, :new]

  depends_on_clusters \
    ApplicationRecord::Iam,
    only: [:new]

  sig { void }
  def index
    available_roles = this_business.roles_assignable_to_target
    selected_tab, query, selected_role = parse_search_query(roles: available_roles)
    role_assignment_fetcher = RoleAssignments::FetchRoleAssignments.new(target: this_business, query:, role: selected_role)
    payload = {
      slug: this_business.slug,
      currentPage: current_page,
      usersCount: role_assignment_fetcher.total_user_role_assignments,
      teamsCount: role_assignment_fetcher.total_business_team_role_assignments,
      hasWriteAccess: viewer_permissions[:write],
      selectedTab: selected_tab,
      canViewEnterpriseTeams: this_business.owner?(current_user),
      avatarOrgs: avatar_orgs,
      availableRoles: RoleAssignments::Types::Role.from_enterprise_roles(available_roles),
      selectedRole: selected_role.present? ? RoleAssignments::Types::Role.from_model(selected_role) : nil,
    }

    if selected_tab == RoleAssignments::SearchHelper::SelectedTab::Team
      payload[:assignments] = role_assignment_fetcher.paginate_business_team_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:teamsCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    else
      payload[:assignments] = role_assignment_fetcher.paginate_user_role_assignments(page: current_page)
      payload[:pageCount] = (payload[:usersCount].to_f / RoleAssignments::FetchRoleAssignments::PAGE_SIZE).ceil
    end

    render_react_app(
      app_name: "enterprise-role-assignments",
      payload:,
      page_data: {
        selected_link: :enterprise_role_assignments,
        sidebar: :people
      },
      title: "Enterprise role assignments · #{this_business.name}",
    )
  end

  sig { void }
  def new
    roles = RoleAssignments::Types::Role.from_enterprise_roles(EnterpriseRole.visible_roles(this_business), with_fgps: true)

    render_react_app(
      app_name: "enterprise-role-assignments",
      payload: {
        slug: this_business.slug,
        enterpriseName: this_business.name,
        enterpriseTeamOrgAssignmentLimitExceeded: this_business_organizations_count > this_business.business_team_organization_assignment_limit,
        avatarOrgs: avatar_orgs,
        roles:,
      },
      page_data: {
        selected_link: :enterprise_role_assignments,
        sidebar: :people
      },
      title: "Assign enterprise role · #{this_business.name}",
    )
  end

  sig { void }
  def create
    assignment_info = JSON.parse(request.body.read)
    role = EnterpriseRole.find_by(id: assignment_info["role_id"].to_i)

    if role.nil? || !role.visible_for_owner?(this_business)
      return render status: :unprocessable_entity, json: { success: false, error: "Unable to assign role." }
    end

    assignee = case assignment_info["assignee_type"]
    when "user"
      User.find_by(id: assignment_info["assignee_id"])
    when "businessteam"
      if current_business.erp_feature_enabled?(:enterprise_teams_crud)
        BusinessTeam.find_by(id: assignment_info["assignee_id"])
      end
    end

    if assignee.nil?
      return render status: :unprocessable_entity, json: { success: false, error: INVALID_ASSIGNEE_ERROR }
    end

    result = current_business.grant_enterprise_role(assignee:, role:)

    if result.success?
      message = "#{assignee_display_name(assignee)} has been assigned the #{role.display_name} role for #{this_business.name}"
      render status: :ok, json: { success: true, message:, redirect_url: enterprise_role_assignments_path(this_business) }
    else
      default_error = "Failed to assign role #{role.display_name} to #{assignee_display_name(assignee)}."
      error = result.reason ? ROLE_ASSIGNMENT_ERRORS.fetch(result.reason, result.reason) : default_error

      render status: :unprocessable_entity, json: { success: false, error: }
    end
  end

  sig { void }
  def destroy
    actor_type = params[:actor_type].downcase
    actor_id = params[:actor_id]
    role_id = params[:role_id]&.to_i

    if actor_type != "user" && actor_type != "businessteam"
      return render status: :unprocessable_entity, json: { success: false, error: "Unable to unassign role. Invalid actor type: #{actor_type}." }
    end

    begin
      assignee = actor_type == "user" ? User.find_by(id: actor_id) : BusinessTeam.find_by(id: actor_id)

      if assignee.nil? || (actor_type == "user" && !current_business.member?(assignee)) || (actor_type == "businessteam" && assignee.business != current_business)
        return render status: :unprocessable_entity, json: { success: false, error: "Invalid actor for enterprise role removal. Invalid #{actor_type}: #{actor_id}." }
      end

      enterprise_role = EnterpriseRole.find_by(id: role_id)

      if enterprise_role.nil? || !enterprise_role.visible_for_owner?(this_business)
        return render status: :unprocessable_entity, json: { success: false, error: "Invalid role for enterprise role removal. Invalid role: #{role_id}." }
      end

      Permissions::Granters::EnterpriseRoleGranter.revoke_role(actor: assignee, target: current_business, role: enterprise_role)
    rescue ActiveRecord::ActiveRecordError, ::Permissions::Granters::RoleGranter::GrantFailure
      return render status: :unprocessable_entity, json: { success: false, error: "Invalid role for enterprise role removal. Failed to revoke role #{enterprise_role&.display_name} from #{actor_type}: #{assignee}." }
    end

    assignee_text = assignee.is_a?(User) ? assignee.safe_profile_name : "the #{assignee.name} enterprise team"
    render status: :ok, json: {
      success: true,
      message: "The #{enterprise_role.display_name} role for #{current_business.name} has been removed from #{assignee_text}.",
    }
  end

  private

  sig { void }
  def custom_enterprise_roles_enabled
    render_404 unless this_business&.custom_enterprise_roles_supported?
  end

  sig { void }
  def read_enterprise_roles_required
    render_404 unless viewer_permissions[:read]
  end

  sig { void }
  def write_enterprise_roles_required
    unless viewer_permissions[:write]
      respond_to do |format|
        format.html { render_404 }
        format.json { render status: :forbidden, json: { success: false, error: "You do not have sufficient permissions to perform this action." } }
      end
    end
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def viewer_permissions
    return { read: false, write: false } unless current_user && this_business

    permissions = Authz.domain.check_multiple_permissions(
      current_user,
      [:read_enterprise_custom_enterprise_role, :write_enterprise_custom_enterprise_role],
      this_business,
    )
    {
      read: permissions[:read_enterprise_custom_enterprise_role],
      write: permissions[:write_enterprise_custom_enterprise_role],
    }
  end

  sig { params(assignee: T.any(User, BusinessTeam)).returns(String) }
  def assignee_display_name(assignee)
    assignee.is_a?(User) ? assignee.safe_profile_name : assignee.name
  end
end
