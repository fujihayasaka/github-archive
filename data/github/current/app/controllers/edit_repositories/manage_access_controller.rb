# typed: false
# frozen_string_literal: true

class EditRepositories::ManageAccessController < AbstractRepositoryController
  before_action :login_required
  before_action do
    render "repositories/states/trade_controls_read_only" if current_repository.trade_controls_read_only?
  end
  before_action :sudo_filter, only: [:add_member, :members_toolbar_actions, :update_members]
  before_action :ensure_admin_access
  before_action :only_org_access, only: [:role_details, :update_members]
  before_action :ensure_custom_roles_enabled, only: :role_details
  after_action :enqueue_sync_package_access_job, only: [:add_member, :update_members, :remove_members]

  layout "repository"
  javascript_bundle :settings

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:add_member, :update_members],
    key: :invite_rate_limit_key,
    log_key: :invite_rate_limit_log_key,
    # allow 40 per 5 minutes
    max: 40,
    ttl: 5.minutes,
    at_limit: :invite_rate_limit_recorder

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:role_details]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:members_toolbar_actions]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:role_details]

  def add_member # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do
      member_type, member = params[:member].to_s.split("/")
      begin
        role = if current_repository.in_organization?
          current_repository.repository_action_from_role_name!(params[:role])
        else
          # collaborators on user-owned repositories can only be given write permission
          :write
        end
      rescue Role::FGPsNotSupportedError, Role::InvalidPermissionError, Role::InvalidCustomRoleError => e
        flash[:error] = Role.error_message_from_exception(e, permission: params[:role], repository: current_repository)
        redirect_to :back
        return
      end

      case member_type
      when "user"
        add_user(member, role: role)
      when "team"
        add_team(member.to_i, role: role)
      else
        render_404
      end
    end
  end

  def update_members # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do
      begin
        action = current_repository.repository_action_from_role_name!(params[:role])
      rescue Role::FGPsNotSupportedError, Role::InvalidPermissionError, Role::InvalidCustomRoleError => e
        flash[:error] = Role.error_message_from_exception(e, permission: params[:role], repository: current_repository)
        redirect_to :back and return
      end

      enqueued_jobs = false

      if params[:user_ids]&.any?
        members = fetch_members_by_ids(action_filter: action)
        GitHub.dogstats.gauge("edit_repositories.update_members.count", members.count, tags: ["member_type:member", "action:#{action}"])

        org_owner_ids =
          if current_repository.in_organization?
            current_repository.owner.admin_ids(actor_ids: members.pluck(:id))
          else
            []
          end

        user_roles = current_repository.direct_roles_for(members, actor_type: "User")
        user_roles.each do |member, role|
          next if org_owner_ids.include?(member.id)

          if role != action
            current_repository.enqueue_update_member(member, action: action, actor: current_user)
            enqueued_jobs = true
          end
        end
      end

      if params[:invitation_ids]&.any?
        invitations = fetch_invitations(params[:invitation_ids])
        GitHub.dogstats.gauge("edit_repositories.update_members.count", invitations.count, tags: ["member_type:invitee", "action:#{action}"])

        invitations.each do |invitation|
          unless invitation.permissions == action.to_s
            invitation.enqueue_update_repo_permissions(setter: current_user, action: action)
            enqueued_jobs = true
          end
        end
      end

      if params[:team_ids]&.any?
        teams = fetch_teams_by_ids
        GitHub.dogstats.gauge("edit_repositories.update_members.count", teams.count, tags: ["member_type:team", "action:#{action}"])

        teams.each do |team|
          unless current_repository.direct_role_for(team) == action
            team.enqueue_update_repo_permissions(repo: current_repository, action: action)
            enqueued_jobs = true
          end
        end
      end

      if enqueued_jobs
        flash[:notice] = "Permissions will be updated for the selected members. Please wait a few minutes and then refresh the page to see your changes."
      else
        flash[:notice] = "No permissions required updating."
      end
      redirect_to :back and return
    end
  end

  def remove_members # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do
      if params[:invitation_ids]&.any?
        invitations = fetch_invitations(params[:invitation_ids])
        GitHub.dogstats.gauge("edit_repositories.remove_members.count", invitations.count, tags: ["member_type:invitee"])

        invitations.each do |invitation|
          invitation.enqueue_cancel_invitation(actor: current_user)
        end
      end

      if params[:user_ids]&.any?
        members = fetch_members_by_ids(action_filter: :none)
        GitHub.dogstats.gauge("edit_repositories.remove_members.count", members.count, tags: ["member_type:member"])

        members.each do |member|
          current_repository.enqueue_remove_member(member, remover: current_user)
        end
      end

      if params[:team_ids]&.any?
        teams = fetch_teams_by_ids
        GitHub.dogstats.gauge("edit_repositories.remove_members.count", teams.count, tags: ["member_type:team"])

        teams.each do |team|
          team.enqueue_remove_repository(current_repository)
        end
      end

      # If current user removes themself, we need to redirect away from the page
      if members&.include?(current_user)
        if current_repository.emu_org_owned?
          role = "an administrator"
        else
          role = "a collaborator"
        end

        redirect_to "/", flash: { notice: "Removed yourself as #{role} of #{current_repository.name_with_display_owner}" }
      else
        redirect_to :back, flash: { notice: "The selected members will be removed from #{current_repository.name_with_display_owner}. Please wait a few minutes and then refresh the page to see your changes." }
      end
    end
  end

  def members_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do
      selected = {}
      selected[:user_ids] = direct_member_ids + collaborator_ids if params[:user_ids].present?
      if params[:invitation_ids].present?
        selected[:invitation_ids] = current_repository.repository_invitations.where(id: params[:invitation_ids].map(&:to_i)).pluck(:id)
      end
      if params[:team_ids].present?
        if check_business_teams?
          teams = Orgs.domain.teams.teams_for_repo(repo_id: current_repository.id, team_ids: params[:team_ids])
          selected[:team_ids] = teams.pluck(:id)
        else
          selected[:team_ids] = current_repository.teams.where(id: params[:team_ids].map(&:to_i)).pluck(:id)
        end
      end

      respond_to do |format|
        format.html do
          render partial: "edit_repositories/pages/members_toolbar_actions",
            locals: {
              view: create_view_model(EditRepositories::Pages::MemberToolbarActionsView,
                repository: current_repository,
                selected_ids: selected
              )
            }
        end
      end
    end
  end

  def role_details # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      ::EditRepositories::Pages::RoleDetailsView,
      repository: current_repository,
      organization: current_repository.organization
    )
    render "edit_repositories/pages/role_details", locals: { view: view }
  end

  private

  def add_user(member, role:)
    begin
      if current_repository.is_enterprise_managed?
        if User.valid_email?(member)
          invitee = User.find_by_email(member, business: current_repository.enterprise_managed_business)
        else
          invitee = User.find(member)
        end

        result = direct_add_user(
          invitee,
          role: role,
        )
      elsif User.valid_email?(member)
        result = if GitHub.email_invitations_enabled?
          email = member
          RepositoryInvitation.invite_to_repo_by_email(
            email,
            current_user,
            current_repository,
            action: role,
          )
        else
          invitee = User.find_by_email(member)
          if invitee && invitee.publicly_visible_email == member
            direct_add_user(invitee, role: role)
          else
            current_repository.errors.add(:base, :inviting_outside_collaborators, message: "cannot invite outside collaborators")
            { sucess: false, errors: current_repository.errors }
          end
        end
      else
        invitee = User.find(member)
        result = RepositoryInvitation.invite_to_repo(
          invitee,
          current_user,
          current_repository,
          action: role,
        )
      end
    rescue ::Permissions::Granters::RoleGranter::GrantFailure => e
      flash[:error] = e.message
      redirect_back fallback_location: repository_access_management_path(current_repository.owner, current_repository) and return
    end

    role_message = "with #{role} permissions"
    invitee_label = User.valid_email?(member) ? member : invitee.display_login

    if result[:success]
      flash[:notice] = "#{invitee_label} has been added as a collaborator #{role_message if current_repository.in_organization?} on the repository."
    elsif result[:errors]&.details.has_key? :seat_limit
      flash[:seat_limit_error] = result[:errors].details[:seat_limit].first[:error]
    elsif result[:errors].messages.has_key? :rate_limit
      flash[:rate_limit_error] = "You've exceeded the rate limit for number of collaborators that can be invited to a repository within a 24-hour period."
    else
      flash[:error] = result[:errors].messages.values.join(", ")
    end

    redirect_to repository_access_management_path(current_repository.owner, current_repository, guidance_task: params[:guidance_task])
  end

  def direct_add_user(invitee, role:)
    if current_repository.add_member(invitee, current_user, action: role)
      { success: true }
    else
      { success: false, errors: current_repository.errors }
    end
  end

  def check_business_teams?
    current_repository.organization&.business&.enterprise_teams_org_roles_supported?
  end

  def add_team(team_id, role:)
    if check_business_teams?
      team = Orgs.domain.teams.find_team_in_organization(
        business_id: current_repository.organization.business&.id,
        organization_id: current_repository.organization.id,
        team_id: team_id)
    else
      team = current_repository.organization.teams.find_by_id(team_id)
    end

    return render_404 if team.nil?

    if current_repository.teams.include?(team)
      return respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
        wants.json { render json: { error: error_message_for(Team::ModifyRepositoryStatus::DUPE) } }
      end
    end

    if current_repository.can_add_to_team?(team, adder: current_user)
      status = team.add_repository(current_repository, role)

      if status == Team::ModifyRepositoryStatus::SUCCESS
        respond_to do |wants|
          wants.html do
            flash[:notice] = "#{team.combined_slug} has been granted #{role} on the repository."
            redirect_to repository_access_management_path(current_repository.owner, current_repository)
          end
          wants.json do
            direct_access_list = ::RepositoryAccessList.new(repository: current_repository, current_user:)

            repository_roles = ::RepositoryMemberRoles.fetch(
              repository:   current_repository,
              current_user: current_user,
              members:      access_list.user_results,
              teams:        access_list.repository_teams,
            )
            render json: {
              name: team.name,
              html: render_to_string(
                partial: "edit_repositories/admin_screen/access_management/team", locals: {
                  team: team,
                  organization: team.organization,
                  view: create_view_model(
                    EditRepositories::Pages::ManagedAccessPageView,
                    repository: current_repository,
                    current_user:,
                    repository_roles:,
                    direct_access_list:
                  )
                },
                formats: [:html]
              ),
            }
          end
        end
      else
        respond_to do |wants|
          wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
          wants.json { render json: { error: error_message_for(status) } }
        end
      end
    else
      respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
        wants.json { render json: { error: "Team not found" } }
      end
    end
  end

  def direct_member_ids
    member_ids = params[:user_ids].map(&:to_i)

    member_ids & (current_repository.direct_member_ids.to_a - current_repository.outside_collaborators_ids.to_a)
  end

  def collaborator_ids
    member_ids = params[:user_ids].map(&:to_i)

    member_ids & current_repository.outside_collaborators_ids.to_a
  end

  # Internal: fetch members with access to the repo.
  # In the context of org-owned repos, it does not make sense to make the permission lower than the org defaults.
  # If the input action is lower than the default permission, we don't return any org members to be updated.
  #
  # action_filter  - the target permission
  #
  # Returns an ActiveRecord::Relation
  def fetch_members_by_ids(action_filter: :none)
    if current_repository.in_organization?
      member_ids =
        if role_assignable_to_all_members?(action_filter)
          direct_member_ids + collaborator_ids
        else
          collaborator_ids
        end

      User.where(id: member_ids)
    else
      User.where(id: collaborator_ids)
    end
  end

  def role_assignable_to_all_members?(action_filter)
    # action should only be :none when we're using this to fetch members for deletion
    action_filter == :none || role_greater_than_default?(action_filter)
  end

  # Internal: is the passed in role greater than the default role
  # If a custom role is passed in, we check if its base role is greater than
  # the org's default role (if there is one)
  #
  # role - the target permission name
  #
  # Returns Boolean
  def role_greater_than_default?(role)
    default_perm = current_repository.organization.default_repository_permission

    return true unless default_perm
    role =
      if Role.valid_system_role?(role)
        role
      else
        RepositoryRole.custom_role_by_name(role, owner: current_repository.organization).base_role.name
      end

    Ability::ACTION_RANKING[role.to_sym] >= Ability::ACTION_RANKING.fetch(default_perm, 0)
  end

  # Internal: fetch teams with access to the repo.
  #
  # Returns an ActiveRecord::Relation
  def fetch_teams_by_ids
    if check_business_teams?
      Orgs.domain.teams.teams_for_repo(repo_id: current_repository.id, team_ids: params[:team_ids])
    else
      current_repository.organization.teams.where(id: params[:team_ids])
    end
  end

  def fetch_invitations(invitation_ids)
    current_repository.repository_invitations.where(id: invitation_ids)
  end

  # We allow access to the admin page in some cases where we don't allow access
  # to the code. To allow for this, we must override the
  # AbstractRepositoryController#ask_the_gatekeeper method for these cases
  #
  # See AbstractRepositoryController#ask_the_gatekeeper for more details
  def ask_the_gatekeeper
    repo = current_repository
    state = params[:fakestate] if real_user_site_admin?

    super if repo&.private? && (repo&.trade_restricted_by_owner? || current_user&.has_any_trade_restrictions?)

    # Allow disabled accounts to edit their repos
    unless (repository_specified? && repo && repo.disabled?) || state == "disabled"
      super
    end
  end

  # Override RepositoryControllerMethods#privacy_check.
  def privacy_check
    permission = current_repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync

    if ![:maintain, :admin].include?(permission)
      if logged_in? && current_user.site_admin?
        render "admin/locked_repo"
      else
        render_404
      end
    end
  end

  def at_least_maintain_required
    role = current_repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
    render_404 if !role || Ability::ACTION_RANKING[role] < Ability::ACTION_RANKING[:maintain]
  end

  def only_org_access
    render_404 unless current_repository.in_organization?
  end

  def ensure_custom_roles_enabled
    render_404 unless current_repository.owner.custom_roles_supported?
  end

  def enqueue_sync_package_access_job
    Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: current_repository) if current_repository
  end

  def invite_rate_limit_key
    "repository_invite_limiter.#{current_user&.id}"
  end

  def invite_rate_limit_log_key
    "repository_invite_limiter_log.#{current_user&.id}"
  end

  def invite_rate_limit_recorder
    GitHub.dogstats.increment("rate_limited", tags: [
      "controller:#{controller_name}",
      "spammy:#{current_user&.spammy?}"
    ])
  end
end
