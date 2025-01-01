# typed: true
# frozen_string_literal: true

class Stafftools::Users::OrgRoleAssignmentsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include GitHub::Memoizer

  before_action :ensure_org_not_user
  before_action :ensure_user_exists
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  javascript_bundle :"org-roles"
  layout :security_layout

  preload_features [
    :authz_org_role_assignments_stafftools_queries,
    :authz_org_role_assignments_stafftools_remove_counts
  ], only: :index

  def index
    index_params = search_parameters
    query_hash = OrganizationRole.parse_query(index_params[:query])

    parsed_query = ActiveRecord::Base.sanitize_sql_like(query_hash[:query]&.to_s&.strip || "")
    assignment_tab = OrgRoles::AssignmentListComponent::AssignmentTab.try_deserialize(query_hash[:is])
    assignment_tab ||= OrgRoles::AssignmentListComponent::AssignmentTab::User
    actor_type = assignment_tab == OrgRoles::AssignmentListComponent::AssignmentTab::User ? "User" : "Team"

    role = nil
    if query_hash[:role].present?
      role = OrganizationRole.visible_roles(this_user).find { |role| role.name == query_hash[:role] }
    end

    current_organization = this_user
    if current_user.feature_enabled?(:authz_org_role_assignments_stafftools_queries)
      assignee_data = RoleAssignmentList::OrgRoleAssignees.new(
        organization: current_organization,
        role_ids: [role&.id],
        direct_only: false
      )

      if current_user.feature_enabled?(:authz_org_role_assignments_stafftools_remove_counts)
        team_count = nil
        user_count = nil
      else
        team_count = team_scope(assignee_ids: assignee_data.team_assignee_ids, query: parsed_query).count
        user_count = user_scope(assignee_ids: assignee_data.user_assignee_ids, query: parsed_query).count
      end

      paginated_assignees = assignee_scope(assignee_ids: assignee_data.ids(actor_type), query: parsed_query, type: assignment_tab).page(index_params[:page]).to_a
      assignment_data = assignee_data.assignments_for(assignees: paginated_assignees.to_a)
    else
      assignment_data = RoleAssignmentList::OrgRoleAssignments.new(
        organization: current_organization,
        actor_type:,
        role_ids: [role&.id],
        direct_only: false
      )
      if current_user.feature_enabled?(:authz_org_role_assignments_stafftools_remove_counts)
        team_count = nil
        user_count = nil
      else
        team_count = team_scope(assignee_ids: assignment_data.team_assignee_ids, query: parsed_query).count
        user_count = user_scope(assignee_ids: assignment_data.user_assignee_ids, query: parsed_query).count
      end

      paginated_assignees = assignee_scope(assignee_ids: assignment_data.assignee_ids, query: parsed_query, type: assignment_tab).page(index_params[:page]).to_a
    end

    visible_org_roles = OrganizationRole.visible_roles(this_user)

    render "stafftools/organizations/roles/assignments/index", locals: {
      organization: this_user,
      query_hash: query_hash,
      active_tab: assignment_tab,
      user_count: user_count,
      team_count: team_count,
      assignees: paginated_assignees,
      assignment_data: assignment_data,
      visible_roles: visible_org_roles,
    }
  end

  private

  def search_parameters
    params.permit(:query, :utf8, :page, :user_id, :organization_id)
  end

  def user_scope(assignee_ids:, query:)
    user_scope = User.where(id: assignee_ids)

    if query.present?
      user_scope = user_scope.merge(User.where("users.login LIKE ?", "%#{query}%"))
    end
    user_scope
  end

  def team_scope(assignee_ids:, query:)
    team_scope = Team.where(id: assignee_ids)

    if query.present?
      team_scope = team_scope.merge(Team.where("teams.slug LIKE ?", "%#{query}%"))
    end
    team_scope
  end

  def assignee_scope(assignee_ids:, query:, type:)
    assignees = if type == OrgRoles::AssignmentListComponent::AssignmentTab::User
      scope = user_scope(assignee_ids:, query:)
      scope.order("login ASC")
    else
      scope = team_scope(assignee_ids:, query:)
      scope.order("slug ASC")
    end
    assignees
  end
end
