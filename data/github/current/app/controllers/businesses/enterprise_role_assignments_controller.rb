# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseRoleAssignmentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include RoleAssignments::SearchHelper

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
    selected_tab, query = parse_search_query
    role_assignment_fetcher = RoleAssignments::FetchRoleAssignments.new(target: this_business, query:)
    payload = {
      slug: this_business.slug,
      currentPage: current_page,
      usersCount: role_assignment_fetcher.total_user_role_assignments,
      teamsCount: role_assignment_fetcher.total_business_team_role_assignments,
      hasWriteAccess: viewer_permissions[:write],
      selectedTab: selected_tab,
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
    roles = EnterpriseRole.custom_roles_for_enterprise(this_business).map do |role|
      {
        id: role.id,
        name: role.name,
        description: role.description,
        icon: role.octicon,
        fgpMetadata: {
          'Enterprise': EnterpriseFgpMetadata.for_role(role)
        }
      }
    end

    render_react_app(
      app_name: "enterprise-role-assignments",
      payload: {
        slug: this_business.slug,
        enterpriseName: this_business.name,
        roles: roles,
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
    role = EnterpriseRole.find_by(id: assignment_info["role_id"], owner_id: this_business.id)
    if role.nil?
      return render status: :unprocessable_entity, json: { success: false, error: "Unable to assign role." }
    end

    assignee = case assignment_info["assignee_type"]
    when "user"
      user = User.find_by(id: assignment_info["assignee_id"])
      current_business.unaffiliated_member?(user) ? user : nil
    when "businessteam"
      team = BusinessTeam.find_by(id: assignment_info["assignee_id"])
      (team && team.business == current_business) ? team : nil
    end

    if assignee.nil?
      return render status: :unprocessable_entity, json: { success: false, error: "Invalid assignee for enterprise role assignment." }
    end

    Permissions::Granters::RoleGranter.new(actor: assignee, target: this_business, role: role).grant_unless_exists!

    message = "#{assignee.is_a?(User) ? assignee.safe_profile_name : assignee.name} has been assigned the #{role.name} role for #{this_business.name}"
    render status: :ok, json: { success: true, message:, redirect_url: enterprise_role_assignments_path(this_business) }
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

      enterprise_role = EnterpriseRole.custom_roles_for_enterprise(current_business).find_by(id: role_id)

      if enterprise_role.nil?
        return render status: :unprocessable_entity, json: { success: false, error: "Invalid role for enterprise role removal. Invalid role: #{role_id}." }
      end

      Permissions::Granters::RoleGranter.new(actor: assignee, target: current_business, role: enterprise_role).revoke_if_exists!
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
end
