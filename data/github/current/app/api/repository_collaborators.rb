# typed: true
# frozen_string_literal: true

class Api::RepositoryCollaborators < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist

  # Set the rate limit family, the lower rate limit is behind the `collaborator_api_rate_limit` feature flag
  rate_limit_as Api::RateLimitConfiguration::OUTSIDE_COLLABORATORS_FAMILY

  VALID_PERMISSIONS = %w(pull triage push maintain admin)
  BATCH_SIZE = 1000

  # List collaborators on a repository.
  get "/repositories/:repository_id/collaborators", operation_id: "repos/list-collaborators" do
    repo = find_repo!
    if repo.public?
      set_forbidden_message "Must have push access to view repository collaborators."
    end
    control_access :list_collaborators,
      resource: repo,
      challenge: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    enforce_valid_permission!(params[:permission])

    permission = params[:permission]
    affiliation = params[:affiliation]

    action = nil
    role_name = nil
    if permission
      action = Repository.permission_to_action(permission)
      if ability_to_query = Ability::NEXT_HIGHEST_ABILITY_FOR_ROLE[action]
        # we are working with a role-based permission (triage/maintain)
        role_name = action
        action = ability_to_query
      end
    end

    # Since we're paginating the list of IDs rather than the scope itself, we
    # need to use WillPaginate::Collection#replace in order to ensure the
    # pagination link headers are correctly added to the response.
    if affiliation == "outside"
      member_ids = repo.outside_collaborators_ids(min_action: action)
    elsif affiliation == "direct"
      member_ids = repo.direct_member_ids
      if action
        member_ids &= repo.direct_or_team_member_ids(viewer: current_user, immediate_only: false, min_action: action)
      end
    else
      member_ids = repo.direct_or_team_member_ids(
        viewer: current_user,
        immediate_only: false,
        min_action: action
      )
    end

    if role_name
      role = Role.internal_role_by_name(role_name)
      actor_ids_by_type = UserRole\
        .where(target: repo, actor_type: %w[Team User])
        .joins(:role)
        .where("roles.id = ? OR roles.base_role_id = ?", role.id, role.id)
        .pluck(:actor_type, :actor_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(actor_type, actor_id), hash|
          hash[actor_type] << actor_id
        end

      user_ids_by_team = if actor_ids_by_type["Team"].any?
        Team.member_ids_of(actor_ids_by_type["Team"], immediate_only: false)
      else
        []
      end

      if affiliation == "direct"
        member_ids += Set.new(actor_ids_by_type["User"]) + (Set.new(user_ids_by_team) & repo.direct_member_ids)
      elsif affiliation == "outside"
        member_ids += Set.new(actor_ids_by_type["User"] + user_ids_by_team) & repo.outside_collaborators_ids
      else
        member_ids += Set.new(actor_ids_by_type["User"] + user_ids_by_team)
      end
    end

    members = member_ids.sort.paginate(pagination)
    members.replace(User.where(id: members).order(:id))

    GitHub::PrefillAssociations.prefill_associations(members, :profile) if medias.api_param?("user-identity")

    # optimization: if filtering on admin, we know the permissions and roles without checking the database
    # (custom roles cannot grant admin, so the role name cannot be a custom role name)
    member_permissions, member_roles = if action == "admin"
      build_admin_permissions_and_roles(members)
    else
      get_member_permissions_and_roles(repo, members)
    end

    if member_ids.difference(member_permissions.keys).any? || member_ids.difference(member_roles.keys).any?
      # temporary - see https://github.com/github/authorization/issues/3371
      GitHub.dogstats.increment "api.list_repo_collaborators.permissionless_collaborator"
    end

    deliver :collaborator_hash, members,
    repo: repo,
    user_permissions: member_permissions,
    user_roles: member_roles
  end

  # Get if user is a collaborator on a repository.
  get "/repositories/:repository_id/collaborators/:username", operation_id: "repos/check-collaborator" do
    repo = find_repo!
    collab = User.find_by_login(params[:username])

    if repo.public?
      set_forbidden_message "Must have push access to view repository collaborators."
    end

    # check permissions to the repo before we check if the username exists
    control_access :list_collaborators,
      resource: repo,
      collab: collab,
      challenge: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if !collab
      deliver_error! 404,
        message: "#{params[:username]} is not a user",
        documentation_url: "/v3/repos/collaborators/#get"
    end

    collab_is_direct_or_team_member = repo.direct_or_team_member_ids(
      viewer: current_user,
      immediate_only: false,
    ).include?(collab.id)

    if collab_is_direct_or_team_member
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Get the given user's highest permission level on the given repository
  get "/repositories/:repository_id/collaborators/:username/permission", operation_id: "repos/get-collaborator-permission-level", resolve_tenant_context: :resolve_tenant_from_repo do
    repo = find_repo!
    collab = User.find_by_login(params[:username])

    if repo.public?
      set_forbidden_message "Must have push access to view collaborator permission."
    end

    control_access :see_user_permission,
      resource: repo,
      collab: collab,
      challenge: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if collab.blank?
      deliver_error! 404,
                     message: "#{params[:username]} is not a user",
                     documentation_url: @documentation_url
    end

    permission = repo.access_level_for(collab) || :none
    deliver(:repository_collaborator_permission, permission, user: collab, repo: repo)
  end

  # Add a user as a collaborator.
  put "/repositories/:repository_id/collaborators/:username", operation_id: "repos/add-collaborator" do
    repo = find_repo!
    collaborator = User.find_by_login(params[:username])

    control_access :add_collaborator,
      resource: repo,
      collab: collaborator,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    # Introducing strict validation of the repositry-collaborator.add
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("repository-collaborator", "add", skip_validation: true)
    if data["permission"].blank? && !data["permissions"].blank?
      GitHub.dogstats.increment "api.add_collaborator_wrong_param"
    end
    permission = data && (data["permission"] || data["permissions"])

    unless collaborator.user?
      deliver_error! 404,
        message: "#{params[:username]} is not a user",
        documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
    end

    action = begin
      # if the permission param was blank, default to :write
      if permission.blank?
        :write
      else
        repo.repository_action_from_role_name!(permission)
      end
    rescue Role::FGPsNotSupportedError,
           Role::InvalidPermissionError,
           Role::InvalidCustomRoleError => e
      if repo.owner.user?   # we handle invalid permissions for user-owned repos separately below
        permission
      else
        deliver_error! 422,
          message: Role.error_message_from_exception(e, permission: permission, repository: repo),
          documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
      end
    end

    unless Role.valid_system_role?(action)
      GitHub.dogstats.increment "collaborator.add_repo_permission.custom_role"
    end

    unless can_assign_action?(repository: repo, user: collaborator, action: action)
      deliver_error! 422,
        errors: "Cannot assign #{collaborator} permission of #{action}",
        documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
    end

    if repo.feature_enabled?(:rescue_not_unique_user_role_grants)
      begin
        if repo.member?(collaborator)
          repo.update_member(collaborator, action: action, actor: current_user)
          return deliver_empty(status: 204)
        end

        if repo.is_enterprise_managed?
          if repo.add_member(collaborator, current_user, action: action)
            return deliver_empty(status: 204)
          else
            deliver_error! 422,
              errors: repo.errors.full_messages,
              documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
          end
        else
          invitation = RepositoryInvitation.find_by(invitee_id: collaborator.id, repository_id: repo.id)
          if invitation.present?
            unless invitation.same_action?(action: action)
              if can_update_invitation_permission?(repository: repo)
                begin
                  invitation.set_permissions(action, current_user)
                rescue ArgumentError, RepositoryInvitation::InsufficientAbilities => e
                  deliver_error! 422,
                    errors: e.message,
                    documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
                end
              else
                GitHub.dogstats.increment "api.add_collaborator_action_update"
              end
            end
          else
            result = RepositoryInvitation.invite_to_repo(collaborator, current_user, repo, action: action)
            unless result[:success]
              deliver_error! 422,
                errors: result[:errors],
                documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
            end
            invitation = result[:invitation]
          end

          return deliver_empty(status: 204) unless invitation
        end

        deliver :repository_invitation_hash, invitation, status: 201
      rescue ActiveRecord::RecordInvalid
        deliver_error! 422,
          errors: "The repository collaborator cannot be added at this time." \
            " Please verify the request and try again.",
          documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
      end
    else
      if repo.member?(collaborator)
        repo.update_member(collaborator, action: action, actor: current_user)
        return deliver_empty(status: 204)
      end

      if repo.is_enterprise_managed?
        if repo.add_member(collaborator, current_user, action: action)
          return deliver_empty(status: 204)
        else
          deliver_error! 422,
            errors: repo.errors.full_messages,
            documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
        end
      else
        invitation = RepositoryInvitation.find_by(invitee_id: collaborator.id, repository_id: repo.id)
        if invitation.present?
          unless invitation.same_action?(action: action)
            if can_update_invitation_permission?(repository: repo)
              begin
                invitation.set_permissions(action, current_user)
              rescue ArgumentError, RepositoryInvitation::InsufficientAbilities => e
                deliver_error! 422,
                  errors: e.message,
                  documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
              end
            else
              GitHub.dogstats.increment "api.add_collaborator_action_update"
            end
          end
        else
          result = RepositoryInvitation.invite_to_repo(collaborator, current_user, repo, action: action)
          unless result[:success]
            deliver_error! 422,
              errors: result[:errors],
              documentation_url: "/rest/reference/repos#add-a-repository-collaborator"
          end
          invitation = result[:invitation]
        end

        return deliver_empty(status: 204) unless invitation
      end

      deliver :repository_invitation_hash, invitation, status: 201
    end
  end

  # Remove a user as a collaborator.
  delete "/repositories/:repository_id/collaborators/:username", operation_id: "repos/remove-collaborator" do
    # Introducing strict validation of the repository-collaborator.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository-collaborator", "delete", skip_validation: true)

    repo = find_repo!
    collab = User.find_by_login(params[:username])

    control_access :remove_collaborator,
      resource: repo,
      collab: collab,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo, ignore_archived: true)

    repo.remove_member(collab, current_user)

    deliver_empty(status: 204)
  end

  def resolve_tenant_from_repo
    Repositories::Public.resolve_tenant(id: params[:repository_id])
  end

  private

  def get_member_permissions_and_roles(repo, members)
    GitHub::PrefillAssociations.prefill_batch_method(members, :action_and_role_level_for, repo)
    maps = members.each_with_object({ permissions: {}, roles: {} }) do |member, result|
      action, role = member.action_and_role_level_for(repo)
      result[:permissions][member.id] = Repository.permissions_hash(action) unless role.nil?
      result[:roles][member.id] = role unless role.nil?
    end
    [maps[:permissions], maps[:roles]]
  end

  def build_admin_permissions_and_roles(members)
    admin_hash = Repository.permissions_hash("admin")
    maps = members.each_with_object({ permissions: {}, roles: {} }) do |member, result|
      result[:permissions][member.id] = admin_hash
      result[:roles][member.id] = "admin"
    end
    [maps[:permissions], maps[:roles]]
  end

  # Private: Checks if the action is allowed to be assigned to user for a repository.
  #
  # repository - the repo the the user is being granted a
  # user - The user being granted the action.
  # action - The name of the role being granted.
  #
  # Returns: True if the user can be assigned the action. False if not.
  def can_assign_action?(repository:, user:, action:)
    return false if repository.nil? || user.nil? || action.nil?

    owner = repository.owner
    if owner.user?
      # Collaborators of user-owned repos can only be assigned "write".
      # Currently this is not enforced, but is a known issue.
      #
      # https://github.com/github/authorization/issues/2633
      if action.to_s != "write"
        return false if GitHub.flipper[:validate_user_repo_permissions].enabled?(owner)
        GitHub.dogstats.increment "api.invalid_permission_collaborator.user"
      end
      return true
    end

    # No restrictions if the user is not a member of the org.
    return true unless owner.member?(user)

    org_base_role = owner.default_repository_permission
    return true if org_base_role == :none

    action_role = RepositoryRole.by_name(perm: action, org: owner, retrieve_base_role: false)
    ranking_role = action_role.custom? ? action_role.base_role : action_role
    action_rank = Ability::ACTION_RANKING[ranking_role.name.to_sym]
    org_role_rank = Ability::ACTION_RANKING[org_base_role]
    can_assign = action_rank >= org_role_rank

    # Org members must have a role greater or equal to the org base role.
    # Currently, it is possible to assign read/write to an org member via the
    # REST API even if read/write are less than the org base role. See
    # https://github.com/github/authorization/issues/2591.
    #
    # If :restrict_org_repo_permissions is on, we enforce disallowing all roles
    # less than the org base role. If it's off, we allow read/write to be assigned
    # even if they're less than the org base role, but disallow triage/maintain/custom
    # role if they are less than the org base role.
    return can_assign if GitHub.flipper[:restrict_org_repo_permissions].enabled?(owner)

    # Emit metric if this request is assigning an ability less than the org base role.
    GitHub.dogstats.increment "api.invalid_permission_collaborator.org_user" if !can_assign && Role::PRIMARY_REPO_BASE_ROLES.include?(action)

    # Return true if action is an ability or it is a system role greater than the org base role.
    return Role::PRIMARY_REPO_BASE_ROLES.include?(action_role.name) || can_assign unless action_role.custom?

    # At this point, action is a custom role. Only allow custom roles equal or
    # greater than the org base role.
    can_assign
  end

  # Check if we can update the permission of an invitation. Return true if the repository's
  # owner (org or user) has the :api_updates_invite_permission flag on.
  #
  # repository - repository to check
  #
  # Returns: Boolean
  def can_update_invitation_permission?(repository:)
    return false if repository.nil?

    GitHub.flipper[:api_updates_invite_permission].enabled?(repository.owner)
  end

  def enforce_valid_permission!(permission)
    if permission && !VALID_PERMISSIONS.include?(permission)
      deliver_error! 422,
          message: "The permission '#{permission}' is not valid. Supported values are: #{VALID_PERMISSIONS.join(', ')}.",
          documentation_url: @documentation_url
    end
  end
end
