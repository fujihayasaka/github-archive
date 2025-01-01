# typed: true
# frozen_string_literal: true

class Orgs::OrgRoleAssignmentsController < Orgs::Controller
  include BaseHelpers::Helpers
  include GitHub::Memoizer

  before_action :login_required
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    only: [:index, :suggestions]

  javascript_bundle :"org-roles"

  def index
    index_params = search_parameters
    query_hash = OrganizationRole.parse_query(index_params[:query])

    parsed_query = ActiveRecord::Base.sanitize_sql_like(query_hash[:query]&.to_s&.strip || "")
    assignment_tab = OrgRoles::AssignmentListComponent::AssignmentTab.try_deserialize(query_hash[:is])
    assignment_tab ||= OrgRoles::AssignmentListComponent::AssignmentTab::User
    actor_type = assignment_tab == OrgRoles::AssignmentListComponent::AssignmentTab::User ? "User" : "Team"

    role = nil
    if query_hash[:role].present?
      # lookup the supplied role name in the preset System Role metadata
      if GitHub.system_all_repo_roles_enabled?
        system_role_name = OrganizationRole::SYSTEM_ROLE_METADATA.select { |_, value| value[:display_name] == query_hash[:role] }.keys.first
        search_name = system_role_name ? system_role_name.to_s : query_hash[:role]
      else
        search_name = query_hash[:role]
      end
      role = OrganizationRole.visible_roles(current_organization).find { |role| role.name == search_name }
    end

    if current_organization.feature_enabled?(:limit_org_role_assignments_queries)
      assignee_data = RoleAssignmentList::OrgRoleAssignees.new(
        organization: current_organization,
        role_ids: [role&.id],
        direct_only: false
      )
      team_count = team_scope(assignee_ids: assignee_data.team_assignee_ids, query: parsed_query).count
      user_count = user_scope(assignee_ids: assignee_data.user_assignee_ids, query: parsed_query).count

      paginated_assignees = assignee_scope(assignee_ids: assignee_data.ids(actor_type), query: parsed_query, type: assignment_tab).page(index_params[:page]).to_a
      assignment_data = assignee_data.assignments_for(assignees: paginated_assignees.to_a)
    else
      assignment_data = RoleAssignmentList::OrgRoleAssignments.new(
        organization: current_organization,
        actor_type:,
        role_ids: [role&.id],
        direct_only: false
      )
      team_count = team_scope(assignee_ids: assignment_data.team_assignee_ids, query: parsed_query).count
      user_count = user_scope(assignee_ids: assignment_data.user_assignee_ids, query: parsed_query).count

      paginated_assignees = assignee_scope(assignee_ids: assignment_data.assignee_ids, query: parsed_query, type: assignment_tab).page(index_params[:page]).to_a
    end

    visible_org_roles = OrganizationRole.visible_roles(current_organization)
    defined_custom_org_roles = OrganizationRole.custom_roles_for_org(current_organization).to_a

    render "settings/organization/org_role_assignments/index", locals: {
      organization: current_organization,
      query_hash: query_hash,
      active_tab: assignment_tab,
      user_count: user_count,
      team_count: team_count,
      assignees: paginated_assignees,
      assignment_data: assignment_data,
      custom_org_roles: defined_custom_org_roles,
      visible_roles: visible_org_roles
    }
  end

  def destroy
    actor_type = params[:actor_type].downcase
    actor_id = params[:actor_id]
    role_id = params[:role_id]&.to_i

    if actor_type != "user" && actor_type != "team"
      flash[:error] = "Invalid actor type: #{actor_type}"
      return redirect_to settings_org_role_assignments_path
    end

    error_message = nil
    begin
      assignee = nil
      if actor_type == "user"
        assignee = User.find_by(id: actor_id) if actor_type == "user"

        if assignee.nil? || !current_organization.member?(assignee)
          return render json: { error: "Invalid actor for organization role removal." }, status: 422
        end
      else
        assignee = Team.find_by(id: actor_id, organization: current_organization)
        if assignee.nil?
          return render json: { error: "Invalid actor for organization role removal." }, status: 422
        end
      end

      org_role = OrganizationRole.custom_roles_for_org(current_organization).find_by(id: role_id)
      if org_role.nil?
        org_role = OrganizationRole.visible_preset_roles(current_organization).find { |role| role.id == role_id }
      end

      if org_role.nil? && current_organization.business.present? && current_organization.business.feature_enabled?(:enterprise_custom_organization_roles)
        # NOTE(assyadh): this can be combined with custom_roles_for_org once the ff is removed.
        org_role = OrganizationRole.custom_roles_from_business(current_organization.business).find_by(id: role_id)
      end

      if org_role.nil?
        return render json: { error: "Invalid role for organization role removal." }, status: 422
      end

      flash_warn = osm_v1_revocation_message # Needs to be called before the role is revoked since the logic relies on knowing the age of the assignment
      result = current_organization.revoke_org_role(assignee: assignee, role: org_role)
    rescue ActiveRecord::ActiveRecordError
      error_message = "Something went wrong. Could not remove role at this time."
    end

    assignee_login = assignee.login_for_api if assignee.is_a?(User)
    assignee_login = assignee.slug if assignee.is_a?(Team)

    if !result&.success?
      error_message = "Failed to revoke role #{org_role&.display_name} from #{actor_type}: #{assignee_login}."
    end

    if error_message
      GitHub.dogstats.increment("custom_org_role_assignment.#{actor_type}.deleted", tags: ["result:fail"])
      flash[:error] = error_message
    else
      GitHub.dogstats.increment("custom_org_role_assignment.#{actor_type}.deleted", tags: ["result:success"])
      flash[:notice] = "#{org_role&.display_name} role was successfully removed from #{actor_type}: #{assignee_login}."
      flash[:warn] = flash_warn
    end

    redirect_to settings_org_role_assignments_path
  end

  def create
    assignee_type, assignee_id = assignment_parameters[:assignee].to_s.split("/")
    role_id = assignment_parameters[:role_id].to_i

    assignee = case assignee_type
    when "user"
      user = User.find_by(id: assignee_id)
      current_organization.member?(user) ? user : nil
    when "team"
      Team.find_by(id: assignee_id, organization: current_organization)
    end

    if assignee.nil?
      flash[:error] = "Invalid assignee for organization role assignment."
      redirect_to settings_org_role_assignments_path(current_organization)
      return
    end

    role = OrganizationRole.custom_roles_for_org(current_organization).find_by(id: role_id)

    if role.nil?
      role = OrganizationRole.visible_preset_roles(current_organization).find { |role| role.id == role_id }
    end

    if role.nil? && current_organization.business.present? && current_organization.business.feature_enabled?(:enterprise_custom_organization_roles)
      role = OrganizationRole.custom_roles_from_business(current_organization.business).find_by(id: role_id)
    end

    if role.nil?
      flash[:error] = "Invalid role for organization role assignment."
      redirect_to settings_org_role_assignments_path(current_organization)
      return
    end

    # grant role handles most of the validations and returns error messages
    result = current_organization.grant_org_role(assignee: assignee, role: role)

    if result.success
      GitHub.dogstats.increment("custom_org_role_assignment.#{assignee_type}.created", tags: ["result:success"])
      flash[:notice] = "#{assignee} has been added to #{role.display_name} for #{current_organization}."
    else
      GitHub.dogstats.increment("custom_org_role_assignment.#{assignee_type}.created", tags: ["result:fail"])
      flash[:error] = result.reason
    end

    redirect_to settings_org_role_assignments_path(current_organization)
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    autocomplete_query = AutocompleteQuery.new(
      current_user,
      params[:q],
      organization: current_organization,
      org_members_only: true,
      include_teams: true
    )

    render OrgRoles::Assignment::AssigneeAutocompleteComponent.new(
      suggestions: autocomplete_query.suggestions.to_a,
    )
  end

  private

  def search_parameters
    params.permit(:query, :utf8, :page, :user_id, :organization_id)
  end

  def user_scope(assignee_ids:, query:)
    scope = User.where(id: assignee_ids)

    if query.present?
      scope = scope.merge(User.where("users.login LIKE ?", "%#{query}%"))
    end
    scope
  end

  def team_scope(assignee_ids:, query:)
    scope = Team.where(id: assignee_ids)

    if query.present?
      scope = scope.merge(Team.where("teams.slug LIKE ?", "%#{query}%"))
    end
    scope
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

  sig { returns(T.nilable(String)) }
  def osm_v1_revocation_message
    # Organization security manager role (OSM) was developed prior to all-repo roles.
    # This v1 version of the role had jobs associated with it that would run periodically
    # to grant direct read abilities to teams assigned the role for all repositories in an organization.
    # After all-repo roles were introduced, we no longer needed to grant these read abilities and eliminated the jobs.
    # We call this updated version of the role that uses all-repo read the v2 version of the role.
    # However we could not clean up the read abilities that were granted on these teams because there was no way to determine
    # whether the grants were done manually by the customer vs automatically by the jobs.
    # We decided it was best to leave the read abilities in place, and to cover ourselves, we would drop a message to the user
    # when they revoke an OSM role that was previously an OSMv1 role they can know to go and clean up these read abilities.

    actor_id = params[:actor_id].to_i
    actor_type = params[:actor_type]
    role_id = params[:role_id].to_i

    return unless role_id == Role.security_manager_role.id
    return unless actor_type.downcase == "team" # OSMv1 was only ever assignable to teams

    if GitHub.enterprise?
      # OSMv1 was upgraded to OSMv2 in GHES 3.14.
      # However we don't have a way to know when the customer upgraded to 3.14
      # to check if their OSM assignments are older than that point, which would indicate that they were previously OSMv1.
      # As a compromise, we assume all OSM teams that have read abilities assigned to them *might* have been OSMv1 teams.
      has_any_repo_read_role = Ability.where(
        actor_id:,
        actor_type:,
        subject_type: "Repository",
        action: 0, # Read action
      ).exists?

      return unless has_any_repo_read_role

      <<~INFO
        As part of assigning the security manager role, this team was also granted read access to all repositories in your organization.
        For teams assigned the role prior to GHES 3.14, read access will remain until you remove the permission from each repository individually.
        To more quickly remove read access, consider deleting the team.
        For teams assigned the role in GHES 3.14 and higher, read access granted by the role will be automatically revoked when the role is removed.
        Read permissions manually assigned to the team will not be affected by the automatic revocation.
      INFO
    else
      # OSMv1 was upgraded to OSMv2 on May 24, 2024.
      assigned_before_upgrade = UserRole.where(
        actor_id:,
        actor_type:,
        role_id:,
        target_id: current_organization.id,
        target_type: Organization.user_role_target_type,
      ).where("created_at <= ?", DateTime.new(2024, 5, 24, 5, 40, 0, 0)).exists?

      return unless assigned_before_upgrade

      <<~INFO
        As part of assigning the security manager role, this team was also granted read access to all repositories in your organization.
        Read access will remain until you remove the permission from each repository individually.
        To more quickly remove read access, consider deleting the team.
        For teams assigned the role after May 24, 2024, read access granted by the role will be automatically revoked when the role is removed.
        Read permissions manually assigned to the team will not be affected by the automatic revocation.
      INFO
    end
  rescue # rubocop:disable Lint/GenericRescue
    # Do nothing because we don't want to fail the request due to trying to get this message.
  end

  memoize def assignment_parameters
    # authenticity_token is provided by the web request, we do not use it
    params.permit(:assignee, :role_id, :organization_id, :authenticity_token)
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of reading the org roles for `this_organization`.
  def read_org_org_roles_required
    if this_organization.nil? || !this_organization.async_can_read_custom_org_roles?(current_user).sync
      render_404
    end
  end
end
