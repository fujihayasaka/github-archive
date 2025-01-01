# typed: true
# frozen_string_literal: true

module Repository::MembershipDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  MENTIONABLES_LIMIT = 1_000
  MAX_ID_LIST_IN_CLAUSE_SIZE = 10_000
  MEMBER_UPDATE_BATCH_SIZE = 100
  VALID_USER_REPO_ACTIONS = %i(write).freeze

  # Public: Get the users that can be assigned to this issue based on who the current user can see.
  #
  # This is a permissions check, not a check against existing assignees. This
  # means the result will include users that are already assigned.
  #
  # CAUTION: This is a potentially expensive method.
  #
  # Returns an array of Users.
  def visible_available_assignees_for(viewer)
    User.where(id: visible_available_assignee_ids(viewer)).includes(:profile)
  end

  def outside_collaborators_ids(min_action: nil)
    collection = Set.new(member_ids(min_action: min_action))

    if in_organization?
      if self.owner&.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
        org_members = T.must(organization).member_ids
      else
        org_members = T.must(organization).member_ids
      end
      collection = collection - org_members
    end

    collection
  end

  def direct_or_team_member_ids(viewer:, immediate_only: true, min_action: nil)
    cache_key = direct_or_team_member_ids_cache_key(viewer.id, immediate_only, min_action, self.id)
    if PermissionCache.key?(cache_key)
      collection = PermissionCache.get(cache_key)
      return collection
    end

    collection = Set.new(member_ids(min_action: min_action))

    if in_organization?
      organization = T.must(self.organization)
      indirect_abilities_enabled = organization.indirect_abilities_enabled?
      default_permission = organization.default_repository_permission
      if default_permission != :none && (!min_action || Ability::ACTION_RANKING[default_permission] >= Ability::ACTION_RANKING[min_action])
        collection.merge(organization.visible_user_ids_for(viewer, type: :all, include_indirect_abilities: indirect_abilities_enabled))

        # Optimization: only do this if min_action is set. With no min_action, `member_ids` (direct repo members) will be a subset of `collection` at this point.
        if min_action && organization.limit_to_public_members?(viewer)
          # It is a little counter-intuitive, but we want to include org members who:
          # 1. have a direct permission on the repository, regardless of level
          # 2. have sufficient permission via org membership and default repo permission
          # We want to do this regardless of their organization visibility because reported permissions (ex: results of repo.action_and_role_level_for)
          # do not account for the visibility of the 'permission source' (ex: team, org membership). If there is a mismatch between reported
          # permissions and the results of filtering on min_action, organization membership may be revealed.
          # So, including these members actually hides their membership status.
          collection.merge(organization.member_ids(actor_ids: member_ids, include_indirect_abilities: indirect_abilities_enabled))
        end
      end

      team_member_ids = all_team_member_ids(include_org_admins: true, immediate_only: immediate_only, min_action: min_action)
      unless team_member_ids.empty?
        if organization.all_teams_visible_for?(viewer)
          collection.merge(team_member_ids)
        else
          collection.merge(organization.visible_users_for(viewer, actor_ids: team_member_ids, include_indirect_abilities: indirect_abilities_enabled).pluck(:id))

          if min_action && organization.limit_to_public_members?(viewer)
            # See comment in default permission section above about why we want to include direct repo members, even if on a secret team.
            collection.merge(member_ids(actor_ids: team_member_ids))
          end
        end
      end

      all_repo_role_members = self.all_repo_role_grants(min_action)

      # Add users
      if all_repo_role_members.key?("User")
        user_ids = organization.visible_user_ids_for(viewer, type: :all, actor_ids: all_repo_role_members["User"], include_indirect_abilities: indirect_abilities_enabled)
        collection.merge(user_ids)
      end

      # Add team members
      if all_repo_role_members.key?("Team")
        if organization.all_teams_visible_for?(viewer)
          all_repo_role_members["Team"].each do |team_id|
            team_users = Team.member_ids_of(team_id, immediate_only: immediate_only)
            collection.merge(team_users)
          end
        else
          visible_team_members = organization.visible_users_for(viewer, actor_ids: all_repo_role_members["Team"]).pluck(:id)
          collection.merge(visible_team_members)
        end
      end

    else
      collection << owner_id
    end

    PermissionCache.set(cache_key, collection)
    collection
  end

  def direct_member_ids(min_action: nil)
    collection = Set.new(member_ids(min_action: min_action))
    collection << owner_id unless in_organization?
    collection
  end

  # Public: the ids of all direct collaborators on this repository, including
  # the owner (unless the owner is an organization).
  def all_member_ids
    if owner.present? && !owner&.organization?
      member_ids << owner_id
    else
      member_ids
    end
  end

  # Public: all direct collaborators on this repository, including the owner
  # (unless the owner is an organization).
  def all_members
    User.where(id: all_member_ids)
  end

  # Users who are most likely to be @mentioned in the context of this
  # repository.
  #
  # - For repositories owned by a User, this includes the owner and
  #   any collaborators.
  # - For repositories owned by an Organization, this includes all members of
  #   the organization with at least read access on the repository, and any
  #   collaborators.
  #
  # Returns a scope.
  def mentionable_users(fields: nil, limit: nil, include_child_teams: true)
    mentionable_users_for(nil, fields: fields, limit: limit,
                          include_child_teams: include_child_teams)
  end

  # Users who are most likely to be @mentioned in the context of this
  # repository with the user.
  #
  # - For repositories owned by a User, this includes the owner and
  #   any collaborators.
  # - For repositories owned by an Organization, this includes all members of
  #   the organization with at least read access on the repository, and any
  #   collaborators.
  # - for public repositories, also include all code contributors, even if they
  #   no longer have explicit access (Abilities) to the repo
  #
  # user - The User to scope to. May be nil.
  # fields - an optional array of fields to select from the users table
  # limit - how many users to return at most; defaults to 1,000
  #
  # Returns a scope.
  def mentionable_users_for(user, fields: nil, limit: nil, include_child_teams: true)
    limit ||= MENTIONABLES_LIMIT

    ids = all_user_ids(viewer: user, include_child_teams: include_child_teams, hide_private_org_owners: true)

    ids = if user
      mentionable_users_ids(user, limit:, user_ids: ids)
    else
      User.from("users FORCE INDEX(PRIMARY)").where(id: ids).not_suspended.pluck(:id)
    end

    ActiveRecord::Base.connected_to(role: :reading) do
      if ids.size < limit && public?
        contribution_user_ids = CommitContributions.domain.contributed_user_ids_by_recency(
          repository: T.cast(self, Repository), # rubocop:todo GitHub/AvoidCast
          limit: limit - ids.size,
        )
        ids |= User.from("users FORCE INDEX(PRIMARY)").where(id: contribution_user_ids).not_suspended.pluck(:id)
      end

      ids = ids[0, limit]
      query = User.where(id: ids, type: "User")
      query = query.select(fields) if fields
      query
    end
  end

  def mentionable_users_ids(user, limit:, user_ids:)
    mentionable_users_ids = T.let([], T::Array[Integer])

    id_list_size = [limit, MAX_ID_LIST_IN_CLAUSE_SIZE].min

    user_ids.each_slice(id_list_size).each do |ids|
      # the max size of ids array will be the limit variable.
      # In the best case, it will perform 1 query with a smaller list of id. All ids will return from the query, and the loop will break.
      # In the worst case it will perform multiple queries. Until either the mentionable_users_ids is filled with enough ids to return the limit or the loop ends.
      # I don't expect it to do more than 2-3 queries, and it is better than doing 1 query with a huge list of ids.
      mentionable_users_ids += User.from("users FORCE INDEX(PRIMARY)").where(id: ids).filter_spam_for(user).not_suspended.pluck(:id)
      break if mentionable_users_ids.size >= limit
    end

    mentionable_users_ids[0, limit]
  end

  # Queues a job to clear leftover permissions/subscriptions for the given
  # user IDs.
  #
  # user_ids - Array of Integer User IDs.
  #
  # Returns nothing.
  def cleanup_old_users(user_ids)
    Team.queue_clear_team_memberships(user_ids, 0, { "repo" => id })
  end

  # The ids of all users that have access to the repository.
  # Includes the following users:
  # - repo owner (if owner is a user)
  # - repo collaborators (direct collaborators)
  # - users with an all repo role granted in org (user or team granted access to all repos in org)
  # - organization members (if org default repository permission is set)
  # - organization team members
  # - organization child team members
  # - organization admins
  #
  # viewer - the User who is currently authenticated, if any
  # include_child_teams: - Boolean. Whether to include child teams or not.
  #                        Note: this will be ignored if there is an
  #                        org default repository permission set.
  def all_user_ids(viewer: nil, include_child_teams: true, hide_private_org_owners: false)
    # Ideally, we would use Abilities here to find all users with read access to
    # the repository. However, in some cases, this could involve checking
    # permissions on thousands of users, so we take some shortcuts to improve
    # performance.
    if org_with_default_permission_owner?
      T.cast(owner, Organization).visible_user_ids_for(viewer) | all_member_ids
    else
      all_member_and_owner_ids(include_child_teams: include_child_teams, viewer: viewer, hide_private_org_owners: hide_private_org_owners)
    end
  end

  # key to use for PermissionCache for #all_member_and_owner_ids
  def all_member_and_owner_ids_key(include_child_teams)
    ["all_member_and_owner_ids", id, include_child_teams]
  end

  # The ids of most users that have access to the repository. Does not include
  # organization members that have repo access via organization
  # default repository permissions. The following users have access:
  # - repo owner (if owner is a user)
  # - repo collaborators (direct collaborators)
  # - users with an all repo role granted in org (user or team granted access to all repos in org)
  # - organization team members
  # - organization child team members
  # - organization admins
  #
  # include_child_teams: - Boolean. Whether to include child teams or not.
  # hide_private_org_owners: - Boolean. Whether to include private org owners in the returned list or not.
  def all_member_and_owner_ids(include_child_teams: true, viewer: nil, hide_private_org_owners: false)
    PermissionCache.fetch(all_member_and_owner_ids_key(include_child_teams)) do

      results = if include_child_teams
        # includes direct, team & child team membership, and organization admin permissions
        enterprise_team_crud_enabled = async_business.then do |business|
          !!business&.erp_feature_enabled?(:enterprise_teams_org_roles)
        end.sync
        connector = [Team]
        connector << BusinessTeam if enterprise_team_crud_enabled
        member_ids = Authorization.service.actor_ids(actor_type: User, subject: self, through: connector)
        member_ids += [owner_id] if owner&.user?

        if owning_organization_id
          owning_org = Organization.includes(:business).find_by!(id: owning_organization_id)
          # Skip the filtering if the viewer is already a member OR if this method is not called from a mentions callsite,
          # in which case we want to include all owners, so that they can be shown in the list of all the users that commented or authored a commit/participated in an issue or PR.
          if owning_org.member?(viewer, include_indirect_abilities: owning_org.indirect_abilities_enabled?) || !hide_private_org_owners
            member_ids += owning_org.admin_ids
          else
            # Only include public owners otherwise
            public_member_ids = owning_org.public_members.pluck(:id)
            # Returns an array containing elements common to both arrays
            member_ids += owning_org.admin_ids & public_member_ids
          end
        end

        member_ids
      else
        all_team_member_ids(include_org_admins: true, hide_private_org_owners: hide_private_org_owners, viewer: viewer) + all_member_ids
      end

      results += self.user_ids_with_all_repo_role_grants(include_child_teams: include_child_teams)

      results.uniq
    end
  end

  # Includes all members and teams members that have access to the repository,
  # as well as organization admins.
  def all_members_and_owners(viewer: nil)
    User.where(id: all_member_and_owner_ids(viewer: viewer))
  end

  # Given a list of users, return an array of user_ids that do not have
  # access to this repo (and thus shouldn't be in the @mentions list)
  # Exception: if the repo owner is an org, optimize_repo_access_checks
  # is true, and the owning org has a lot of members, don't return any
  # id's, as getting the id's for all the members of a large org
  # (e.g. EpicGames) may time out
  #
  # users - list of users to check
  # include_child_teams - Boolean. Whether to include child teams or not.
  #                       Note: #all_user_ids will ignore this param if an
  #                       org default repository permission is set.
  # optimize_repo_access_checks - by default, check that all users returned
  #                               have access to the repo. If optimize_repo_access_checks
  #                               passed in is true, and the owner org has a
  #                               lot of members (> Repository::ORG_MEMBERSHIP_VERIFICATION_LIMIT),
  #                               (e.g. EpicGames) skip the access checks.
  #
  # Returns an array of user_ids that should be excluded. Return of [] either
  # means all users have access, or the org is too large to check.
  def user_ids_to_hide_from_mentions(users, viewer: nil, include_child_teams: true, optimize_repo_access_checks: false)
    return [] if public?

    # if this is an org with lots of members, and we don't already have
    # a result cached, don't hide anyone, as #all_user_ids might time out
    if optimize_repo_access_checks &&
        !org_with_default_permission_owner? &&
        large_membership_org_owner?
      unless PermissionCache.key?(all_member_and_owner_ids_key(include_child_teams))
        # ideally, we'd now populate the cache in the background.
        # Issue to track/discuss: https://github.com/github/github/issues/83848
        return []
      end
    end

    user_ids = if users.first&.respond_to?(:id)
      users.map(&:id).uniq
    else
      # Assume given an array of IDs already
      users
    end

    # Filtering out mannequins
    mannequin_ids = Mannequin.where(id: user_ids).pluck(:id)
    user_ids = user_ids - mannequin_ids

    user_ids_with_repo_access = (all_user_ids(viewer: viewer, include_child_teams: include_child_teams) & user_ids)
    user_ids - user_ids_with_repo_access
  end

  private def large_membership_org_owner?
    owner&.organization? && T.cast(owner, Organization).members_count > Repository::ORG_MEMBERSHIP_VERIFICATION_LIMIT
  end

  # Can we assign issues (or other things) to this user?
  #
  # Returns true if user can be assigned issues.
  def assignable_member?(user)
    return false unless user.is_a?(User)
    return false unless user.assignable_to_issues?
    return true if user.id == owner_id

    available_assignee_ids.include?(user.id)
  end

  # Can we add this user to the repo?
  #
  sig do
    params(addee: T.nilable(User), adder: T.nilable(User), action: T.any(Symbol, String), already_invited: T::Boolean, override_lock: T::Boolean, check_2fa: T::Boolean)
      .returns(T::Boolean)
  end
  def can_add_user?(addee, adder, action: :write, already_invited: false, override_lock: false, check_2fa: true)
    owner = T.must(self.owner)

    if owner.business&.emu_repository_collaborators_enabled?
      if is_enterprise_managed?
        if addee.nil? ||
          !addee.is_enterprise_managed? ||
          enterprise_managed_business != addee.enterprise_managed_business

          errors.add(:base, "User is not a member of the enterprise.")
          return false
        end

        if owner.organization? && !T.cast(owner, Organization).member?(addee)
          owner = T.cast(owner, Organization)
          if owner.enterprise_admins_only_can_invite_outside_collaborators?
            if !enterprise_managed_business&.adminable_by?(adder)
              errors.add(:base, "Only enterprise admins can add repository collaborators.")
              return false
            end
          elsif !owner.members_can_invite_outside_collaborators?
            if !owner.adminable_by?(adder)
              errors.add(:base, "Only organization admins can add repository collaborators.")
              return false
            end
          end
        end
      end
    else
      if is_enterprise_managed?
        if addee.nil? ||
          !addee.is_enterprise_managed? ||
          enterprise_managed_business != addee.enterprise_managed_business ||
          owner.organization? && !T.cast(owner, Organization).member?(addee)

          errors.add(:base, "User is not a member of the enterprise managed organization.")
          return false
        end
      end
    end

    if owner.organization? && RepositoryInvitation.cannot_invite_because_fork_and_not_in_business?(owner, self, addee)
      errors.add(:base, "Users outside of the enterprise account cannot be added to a private or internal fork")
      return false
    end

    if private? && addee&.has_any_trade_restrictions?
      errors.add(:base, "User could not be added")
      return false
    end

    if trade_restricted?
      errors.add(:base, "User could not be added")
      return false
    end

    # if addee will be an outside collaborator to an org, ensure addee is compliant with org's 2FA polices (if addee exists)
    # can remove after https://github.com/github/authorization/issues/4526
    if check_2fa && owner.organization? && addee && !T.cast(owner, Organization).member?(addee) &&
      (!two_factor_requirement_met_by?(addee) || disallowed_two_factor_method_used_by?(addee))
      errors.add(:base, "User must configure two-factor authentication, with only allowed methods.")
      return false
    end

    adders = [adder]
    adders << owner if adder && adder.id != owner_id
    adders.compact!

    actor = adder unless adder.is_a?(Bot)
    actor ||= if (installation = adder&.installation)
      installation
    else
      IntegrationInstallation.with_repository(self).where(integration_id: adder&.integration&.id).first
    end

    if advisory_workspace?
      if actor != organization && !parent_advisory&.workspace_openable_by?(actor)
        errors.add(:base, "You cannot manage this advisory workspace")
        return false
      end
    else
      if actor != organization && !resources.administration.writable_by?(actor)
        errors.add(:base, "You cannot administer this repository")
        return false
      end
    end

    if has_invitation_for?(addee) && !already_invited
      errors.add(:base, "User has already been invited")
      return false
    end

    blocked = addee&.blocked_by?(owner_id)
    unless blocked
      blocked = addee&.blocked_by?(organization&.admins) if owner.organization?
    end

    if blocked
      errors.add(:base, "User is blocked")
      return false
    end

    if addee&.ignore?(*adders)
      errors.add(:base, "User has blocked you")
      return false
    end

    if spammy?
      errors.add(:base, "User could not be added")
      return false
    end

    # Skip if we are in a gh-migrator import process
    if addee&.suspended? && !importing?
      errors.add(:base, "User is suspended")
      return false
    end

    if members.include?(addee)
      errors.add(:base, "User is already a collaborator")
      return false
    end

    if owner == addee
      errors.add(:base, "Repository owner cannot be a collaborator")
      return false
    end

    if !addee&.user?
      errors.add(:base, "Only users can be collaborators")
      return false
    end

    if Organization.transforming?(addee)
      errors.add(:base, "Users being transformed into organizations cannot be added as collaborators")
      return false
    end

    if owner.user? && action != :write
      errors.add(:base, "You can only give write access to user-owned repositories")
      return false
    end

    if owner.user? && private? && !has_seat_for?(addee) && !advisory_workspace?
      errors.add(:base, "You must upgrade your account to add more collaborators.")
      return false
    end

    if owner.organization? && private? && !advisory_workspace?
      if !owner.has_seat_for?(addee)
        errors.add(:seat_limit, "You must purchase at least one more seat to add this user as a collaborator.")
        return false
      end

      if !owner.has_seat_for?(addee, pending_cycle: true)
        errors.add(:base, "You must cancel your pending seat downgrade to add this user as a collaborator.")
        return false
      end
    end

    if !override_lock && lock_on_transferring_ownership?
      errors.add(:base, "The repository is locked due to an ownership transfer.")
      return false
    end

    true
  end

  # Returns a collection of users who have been invited to this repository but
  # have not yet accepted the invitation.
  def invitees
    repository_invitations.includes(:invitee).map(&:invitee)
  end

  # Determine if this repository has an invitation for a particular user.
  def has_invitation_for?(user)
    repository_invitations.where(invitee_id: user.id).any?
  end

  def cancel_all_invitations_from_user(user, actor)
    repository_invitations.where(inviter_id: user.id).each { |i| i.cancel!(actor: actor, force: true) }
  end

  # Internal: Directly add the specified user to the repository, bypassing
  # validation and subscription/notification stuff.
  #
  # ONLY CALL THIS IF YOU KNOW EXACTLY WHAT YOU'RE DOING.
  #
  # addee  - The user to add as a collaborator to this repository.
  # adder  - The user who is adding the addee as a collaborator.
  # action - The level of permission the addee should be given on the
  #          repository. Can be :read, :write, or :admin.
  #
  # Returns nothing.

  def add_member_without_validation_or_notifications(addee, adder = owner, event: false, action: :write, bulk: false)
    adding_repository_collaborator = repository&.organization&.business&.emu_repository_collaborators_enabled? &&
      repository.organization.present? &&
      addee.present? &&
      !repository.organization.members.include?(addee) &&
      !repository.organization.user_is_outside_collaborator?(addee.id) &&
      repository.organization&.business&.enterprise_managed_user_enabled?

    grant(addee, action, grantor: adder)
    Repository::AdvisoryAbilityManager.grant(addee, repository: self, action: action)
    add_member_to_business(addee) if business&.add_collaborator_user_accounts?

    update_collaborator_cache_for_user(addee)

    if licensing_enabled?
      Licensing::SnapshotLicensesJob.perform_later(owner&.business)
      business&.update_license_usage unless bulk
    end

    schedule_package_access_job

    instrument :add_member, user: addee, actor: adder, permission: action
    GlobalInstrumenter.instrument("repo.add_member", {
      user: addee,
      actor: adder,
      repo: self,
      action: :add,
    })

    if adding_repository_collaborator
      log_emu_repository_collaborator_added(addee)
    end
  end

  def add_members(members, adder = owner, event = true)
    members.each do |member|
      add_member(member, adder, bulk: true)
    end
    business&.update_license_usage
  end

  # After ensuring that a user is allowed, adds that user to the repository
  # and subscribes them to notifications.
  #
  # addee - The user to add as a collaborator to this repository
  # adder - The member who is adding the user. Defaults to the repo owner.
  # event - Not used.
  # action - The default permission for the addee.
  # bulk - Is this add performed as part of a bulk add of members
  #
  # Returns true on succees or nil on failure.
  def add_member(addee, adder = owner, event = true, action: :write, bulk: false, override_lock: false)
    if can_add_user?(addee, adder, action: action, override_lock: override_lock)
      add_member_without_validation_or_notifications(addee, adder, action: action, bulk: bulk)
      response = GitHub.newsies.auto_subscribe(addee, self)
      if response.success?
        addee.reload # clear cached associations
      else
        GitHub.newsies.async_auto_subscribe(addee, [id])
      end

      update_collaborator_cache_for_user(addee)
      Contribution.clear_caches_for_user(addee, context: "add_repository_member")

      schedule_package_access_job

      true
    end
  end

  # Removes someone as a collaborator on a repository.
  #
  # Also iterates through any issues the person may have been assigned to and
  # unassigns them. Keep this logic in this method (and not as a callback
  # after a membership is deleted) so we don't inadvertedly remove assignees
  # when a repo goes from personal -> org.
  #
  # removee - The member being removed.
  # remover - The user removing the member. defaults to owner.
  #
  # Returns true if the member was removed, false if they were not removed (invalid removee, or not a member).
  def remove_member(removee, remover = owner)
    # only users can be members of a repository
    return false if !removee.user?

    return false if !disassociate_member(removee, remover)

    RemoveUserFromRepoCleanupJob.perform_later(actor_id: remover.id, member_id: removee.id, repo_id: id)

    removee.reload # clear cached associations

    if licensing_enabled?
      Licensing::SnapshotLicensesJob.perform_later(owner&.business)
    end

    update_collaborator_cache_for_user(removee)
    Contribution.clear_caches_for_user(removee, context: "remove_repository_member")
    business&.update_license_usage

    schedule_package_access_job
    if in_organization? && !organization&.member?(removee) && !organization&.user_is_outside_collaborator?(removee.id)
      RemoveOrgMemberProjectsNextAccessJob.perform_later(organization, removee)
    end

    true
  end

  # Public: enqueues a job to remove a member from the repository
  #
  # removee - The member being removed.
  # remover - The user removing the member. defaults to owner.
  #
  # Returns nothing.
  def enqueue_remove_member(removee, remover:)
    return unless pullable_by?(removee)
    RemoveRepoMemberJob.perform_later(removee, remover: remover, repo: self)
  end

  # Internal: remove all collaborators from this repository.
  #
  # actor - The user clearing the members. Defaults to owner.
  def remove_all_members(actor = owner)
    # dup since members is being modified during the iteration.
    members.dup.each do |member|
      disassociate_member(member, actor)
      cancel_all_invitations_from_user(member, actor)
    end
    OrganizationCollaborator.where(organization_id: organization_id).destroy_all if in_organization?
  end

  # Internal: remove removee from forks of this repository
  #
  # removee - The user being removed from forks
  # remover - The user removing the user from forks
  # context - where the cleanup was called from, ex. "repo.update_member". Used for annotating metrics sent to DataDog.
  def remove_from_forks(removee, remover)
    descendants.each do |repo|
      repo.remove_member(removee, remover)
    end
  end

  # Internal: disassociate a collaborator from this repository.
  #
  # user  - The User being removed as a collaborator.
  # actor - The User responsible for removing the user.
  #
  # Only breaks the direct link between the user and this repo and leaves stars,
  # watching, and issue assignments intact.
  def disassociate_member(user, actor)
    return false unless member?(user)

    with_write do
      # Ensure we remove access to Vulnerability Alerts
      vulnerability_manager.revoke_user_or_team(user)
      revoke user
      Repository::AdvisoryAbilityManager.revoke(user, repository: self, actor: actor)

      # Ensure we remove access to Protected Branches
      ProtectedBranch::AbilityRepositoryManager.revoke(user, repository: self)
    end

    instrument :remove_member, user: user, actor: actor
    GlobalInstrumenter.instrument("repo.remove_member", {
      user: user,
      actor: actor,
      repo: self,
      action: :remove,
    })

    GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
      user: user,
      repository_ids: [id],
    })

    schedule_package_access_job

    true
  end

  def copy_permissions_of(repo, adder = owner)
    return if repo == self || repo.nil?
    add_members(repo.all_members, adder, false)
  end

  # Public: Update a member's permission on this repository.
  #
  # member  - Member whose permission we want to update.
  # action  - The permission to update to. Can be read/write/triage/maintain/admin or a custom role
  # actor   - User doing the update.
  # context - Hash of Strings with the member's previous Role {:old_permission, :old_base_role}
  #           A user might be given the same custom role permission, with a different base role.
  #           In these scenarios, the name is the same, but the Ability must be updated.
  #           For auditing purposes, we need the old Role and it's base role.
  #           A custom role is a user created role which inherits from any Role::VALID_REPO_BASE_ROLES
  #           with an additional set of fine grained permissions.
  #
  # Returns a boolean (true if the update worked, false if it didn't).
  def update_member(member, action:, actor: owner, context: {})
    if in_organization?
      # action must either be a system role or a valid custom role for the given repository
      if !Repository::VALID_ORG_REPO_ACTIONS_AND_ROLES.include?(action) && !Role.valid_custom_role?(action, owner: T.cast(owner, Organization))
        errors.add(:base, "Invalid permission passed")
        return false
      end
    elsif !VALID_USER_REPO_ACTIONS.include?(action)
      errors.add(:base, "Invalid permission passed")
      return false
    end

    if members.exclude?(member)
      errors.add(:base, "User is not yet a collaborator")
      return false
    end

    # if the custom role itself got updated, the old permission can't be obtained directly from Ability records
    # so we leverage the context
    old_role = RepositoryRole.by_name(perm: self.direct_role_for(member), org: self.owner)
    old_role_name = context.dig(:old_permission) || old_role&.name
    old_base_role_name = context.dig(:old_base_role) || old_role&.base_role&.name
    # for system roles we need to use the role name, in the case of a custom role, we need to use the base role
    old_permission = old_base_role_name.nil? ? old_role_name : old_base_role_name

    old_permissions = {
      pull: permission_greater_than_target?(
        old_permission, target: "read"
      ),
      push: permission_greater_than_target?(
        old_permission, target: "write"
      ),
      admin: permission_greater_than_target?(
        old_permission, target: "admin"
      ),
      triage: permission_greater_than_target?(
        old_permission, target: "triage"
      ),
      maintain: permission_greater_than_target?(
        old_permission, target: "maintain"
      )
    }

    grant member, action, grantor: actor
    Repository::AdvisoryAbilityManager.grant(member, repository: self, action: action)

    new_base_role_name = RepositoryRole.by_name(perm: action, org: self.owner, retrieve_base_role: true)&.name

    instrument :update_member,
      user: member,
      actor: actor,
      old_repo_permission: old_role_name.to_sym,
      old_repo_base_role: old_base_role_name&.to_sym,
      new_repo_base_role: new_base_role_name&.to_sym,
      new_repo_permission: action.to_sym,
      old_permissions: old_permissions

    member.reload

    if member != organization && !adminable_by?(member)
      cancel_all_invitations_from_user(member, actor)
      # Ensure we remove access to Protected Branches when the member loses write access
      if action == :read
        ProtectedBranch::AbilityRepositoryManager.revoke(member, repository: self)
      end
    end

    update_collaborator_cache_for_user(member)

    schedule_package_access_job

    true
  end

  # Public: Update a member's permission on this repository via background job.
  #
  # member  - Member whose permission we want to update.
  # action  - The permission to update to. Can be :read, :write, :admin, :triage, :maintain, or a custom role
  # actor   - The user who is performing the update, for audit log instrumentation
  def enqueue_update_member(member, action:, actor:)
    action = evaluate_action(action)
    UpdateMemberRepoPermissionsJob.perform_later(member, action: action, repo: self, actor: actor)
  end

  # Public: returns the provided role name, translated into an Ability action if necessary, if
  # it exists as a valid role for the repository.
  # Raises ArgumentError if the role does not exist or is not supported by the current billing plan
  #
  # role_name             -   name of a role to try
  #
  # Returns: String
  def repository_action_from_role_name!(role_name)
    if Role.valid_system_role?(role_name)   # read/triage/write/maintain/admin/push/pull
      if Role.plan_protected_role?(role_name)   # triage and maintain roles
        raise Role::FGPsNotSupportedError unless fine_grained_permissions_supported?
      end

      # translates pull to :read, and push to :write, the rest are returned as they are
      Repository.permission_to_action(role_name)
    else    # see if this is a custom role
      unless self.owner&.custom_roles_supported?
        raise Role::InvalidPermissionError
      end
      return role_name if Role.valid_custom_role?(role_name, owner: T.cast(owner, Organization))
      raise Role::InvalidCustomRoleError
    end
  end

  # Public: Update organization collaborator cache for the owning Organization if the feature is enabled.
  def update_collaborator_cache
    return unless organization_collaborator_cache_write?
    OrganizationCollaboratorBackfillJob.perform_later(org: organization)
  end

  # Public: Update organization collaborator cache for the owning Organization if the feature is enabled.
  def update_collaborator_cache_for_user(user)
    return unless organization_collaborator_cache_write?
    OrganizationCollaborator.update_for_org_and_user(T.must(organization), user)
  end

  private

  # Private: Schedule a job to update package access inherited from the repository
  #
  # The job calls out to the registry metadata service to list packages associated with this repository,
  # so a background job is used for inherited access reconciliation to allow for retries in the event of
  # connectivity failure or service interruption.
  def schedule_package_access_job
    Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: self)
  end

  # Private: Create a business user account if needed
  def add_member_to_business(user)
    business&.add_user_accounts([user.id], business_roles_bitfield: BusinessUserAccount.roles_bitmask([:outside_collaborator]))
  end

  def log_emu_repository_collaborator_added(addee)
    GitHub.logger.info("EMU repository collaborator added",
      {
        "code.function": "log_emu_repository_collaborator_added",
        "gh.repo.id": id,
        "gh.user.id": addee.id,
        "gh.business.id": repository.organization.business.id,
      }
    )
  end

  def direct_or_team_member_ids_cache_key(viewer_id, immediate_only, min_action, repository_id)
    [
      "direct_or_team_member_ids",
      viewer_id,
      immediate_only,
      min_action,
      repository_id
    ]
  end

  def organization_collaborator_cache_write?
    return false unless in_organization?
    return true if T.must(organization).feature_enabled?(:collaborator_cache_write) || T.must(organization).business&.feature_enabled?(:collaborator_cache_write)
    false
  end
end
