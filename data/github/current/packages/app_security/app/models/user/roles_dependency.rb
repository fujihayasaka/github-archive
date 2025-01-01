# typed: false
# frozen_string_literal: true

module User::RolesDependency
  extend ActiveSupport::Concern

  STAFF = "staff"

  included do
    has_many :user_stafftools_roles, dependent: :destroy
    has_many :stafftools_roles, through: :user_stafftools_roles

    # This will also define async_batch_action_and_role_level_for
    # Note: this method is suitable for actors with a defined relationship to the repository, but
    #       it does not account for repository access that applies to all users (ex: everyone can read a public repo)
    batch_method(:action_and_role_level_for) do |actors, repo|
      actions_by_id, roles_by_id = repo.batch_action_and_role_level_for(actors)
      actors.index_with { |a| [actions_by_id[a.id], roles_by_id[a.id]] }
    end
  end

  # Can this user make and edit blog posts?  Staff, support and blogger roles
  # have this power.
  def blogger?
    employee?
  end

  # Is this user a participant in the GitHub Security Bug Bounty. These users
  # get a special profile badge and may be given early access to features.
  def bounty_hunter?
    !GitHub.enterprise? && team_access?(:bounty_hunters)
  end

  # Is this user a participant in the GitHub Campus Experts program.
  # These users get a special profile badge.
  def campus_expert?
    !GitHub.enterprise? && team_access?(:campus_experts_badge)
  end

  # Public: Indicates if this user is a member of the GitHub Stars program.
  #
  # Returns a Boolean.
  def github_star?
    return @is_stars_member if defined?(@is_stars_member)
    @is_stars_member = !GitHub.enterprise? && team_access?(:github_stars)
  end

  # NB: Whenever a GitHub Employee is hired, we revoke their OAuth applications
  # and SSH keys so that 3rd parties don't inadvertently get access to GitHub code.
  def revoke_new_hire_accesses
    async_revoke_oauth_tokens(:personal_tokens)
    public_keys.each { |key| key.unverify(:new_hire) }
  end

  # Is this user on the @github/employees team? This should be used for
  # behaviors that need to be available to all GitHub staff. User#site_admin?
  # should be used for administrative actions that not all staff need access
  # to.
  # This check returns 'false' if the user has disabled employee mode in the site footer.
  def employee?
    return @is_employee if defined?(@is_employee)
    @is_employee = employee_ignoring_override?
  end

  # Checks if the user is in the @github/employees team.
  # This check ignores the override option provided in the footer.
  def employee_ignoring_override?
    return false if GitHub.enterprise?
    return false if GitHub.multi_tenant_enterprise? && GitHub.flipper[:disable_proxima_employee_team_check].enabled?
    team_access?(:employees) || team_access?(:interns)
  end

  # Used to clear the memo'ized employee status; useful if you need to add
  # add someone as an employee but have already queried if they are.
  #
  # Note: We really should figure out a better way to change this during
  #       employee membership addition.
  def clear_employee_memo
    remove_instance_variable(:@is_employee) if defined?(@is_employee)
  end

  def biztools_user?
    GitHub.billing_enabled? && gh_role == "biz"
  end

  # Let the user pretend not to be an employee. Will cause #employee? to return
  # false.
  #
  # Returns nothing.
  def disable_employee_mode
    @is_employee = false
    @disabled_employee_mode = true
  end

  # Public: Is the user an employee who's disabled employee mode?
  def disabled_employee_mode?
    !!@disabled_employee_mode
  end

  attr_accessor :site_admin

  # Is this user a site admin? Can be set to false using the accessor to
  # temporarily lower a user's status.
  #
  # Site admins include a subset of GitHub staff in the dotcom environment,
  # and administrative users in the enterprise environment.
  def site_admin?
    user? && site_admin_without_two_factor_check? &&
      (!GitHub.require_two_factor_for_site_admin? || two_factor_authentication_enabled?)
  end

  # Working for GitHub isn't the same as getting access to staff features.
  # - For GitHub, this is defined as an employee in the staff role who also
  #   has access to the employees team.
  # - For GHE, this is a user which is explicitely a site_admin
  def site_admin_without_two_factor_check?
    has_staff_role? &&
    (!GitHub.require_employee_for_site_admin? || employee?) &&
    (@site_admin.nil? || @site_admin)
  end

  # Does this GitHubber need access to devtools?
  def github_developer?
    GitHub.devtools_enabled? && gh_role == "dev"
  end

  def has_staff_role?
    defined?(gh_role) && gh_role == STAFF
  end

  # Determines whether the user can unlock private repos.
  def can_unlock_repos?(repository: nil)
    return true if enterprise_admin_unlocking_repo?
    return true if staff_unlocking_repo?
    return true if can_unlock_user_repo?(repository:)

    false
  end

  # staff user on dotcom
  def staff_unlocking_repo?
    return false unless !GitHub.enterprise? && site_admin? # staff user on dotcom
    stafftools_action = { controller: "Stafftools::Repositories::StaffAccessController", action: "unlock" }
    Stafftools::AccessControl.authorized?(self, stafftools_action)
  end

  # GHES admin
  def enterprise_admin_unlocking_repo?
    GitHub.enterprise? && site_admin?
  end

  # Enterprise user unlocking user-owned repo within same business
  def can_unlock_user_repo?(repository: nil)
    return false if repository.nil?

    repo_owner = repository.owner
    return false unless repo_owner.is_a?(::User) && repo_owner.user?
    return false unless GitHub.enterprise? || repo_owner.is_enterprise_managed?

    business = repo_owner.enterprise_managed_business || GitHub.global_business
    business.can_user_unlock_user_namespace_repos?(self)
  end

  # Determines whether the user can unlock private repos, without requesting permission from the owner.
  # This privilege exists only for security & legal purposes.
  def can_unlock_repos_without_owners_permission?
    return false unless site_admin?
    return true if GitHub.enterprise?

    stafftools_action = { controller: "Stafftools::Repositories::StaffAccessController", action: "override_unlock" }
    Stafftools::AccessControl.authorized?(self, stafftools_action)
  end

  # Determines whether the user can unlock fake login as a user.
  def can_fake_login?
    return false unless site_admin?
    return true if GitHub.enterprise?

    stafftools_action = { controller: "Stafftools::SessionsController", action: "impersonate" }
    Stafftools::AccessControl.authorized?(self, stafftools_action)
  end

  # Determines whether the user can impersonate users without an active staff access grant.
  def can_impersonate_users_without_permission?
    return false unless site_admin?
    return false unless access_grant_required_for_user_impersonation?

    stafftools_action = { controller: "Stafftools::SessionsController", action: "override_impersonate" }
    Stafftools::AccessControl.authorized?(self, stafftools_action)
  end

  def access_grant_required_for_user_impersonation?
    !GitHub.enterprise?
  end

  # Determines whether the user can manage Marketplace listings.
  # Users with site admin or biztools access are allowed.
  #
  def can_admin_marketplace_listings?
    site_admin? || biztools_user?
  end

  # Determines whether the user can manage Sponsors listings
  # Users with site admin or biztools access are allowed.
  #
  def can_admin_sponsors_listings?
    site_admin? || biztools_user?
  end

  # Determines whether the user can manage Sponsors newsletter
  # Users with site admin or biztools access are allowed.
  #
  def can_admin_sponsors_newsletters?
    site_admin? || biztools_user?
  end

  # Determines whether the user can manage Repository Actions
  # Users with site admin or biztools access are allowed.
  #
  def can_admin_repository_actions?
    site_admin? || biztools_user?
  end

  # Determines whether the user can manage Repository Stacks
  # Users with site admin or biztools access are allowed.
  #
  def can_admin_repository_stacks?
    site_admin? || biztools_user?
  end

  def can_become_staff?
    !(GitHub.require_employee_for_site_admin? && !employee?)
  end

  # Grant the user site-admin permissions.
  #
  # for .com, this user must be a member of the employees group in order to
  # prevent improper access being granted.
  #
  # reason - a String explanation for why/how the user was given access. Required.
  #
  # Returns false if no reason was provided, true otherwise.
  def grant_site_admin_access(reason)
    return false unless can_become_staff?
    change_role("staff", reason, :promote)
  end

  # Grant the user github-developer permissions.
  #
  # reason - a String explanation for why/how the user was given access. Required.
  #
  # Returns false if no reason was provided, true otherwise.
  def grant_github_developer_access(reason)
    raise "devtools disabled" unless GitHub.devtools_enabled?
    change_role("dev", reason, :grant_github_developer)
  end

  # Grant the user biztools permissions.
  #
  # reason - a String explanation for why/how the user was given access. Required.
  #
  # Returns false if no reason was provided, true otherwise.
  def grant_github_biztools_access(reason)
    raise "billing disabled" unless GitHub.billing_enabled?
    change_role("biz", reason, :grant_biztools_user)
  end

  # Revoke the user's site-admin, biztools, or github-developer permissions.
  #
  # reason - a String explanation for why/how the access was revoked. Required.
  #
  # Returns false if no reason was provided, true otherwise.
  def revoke_privileged_access(reason)
    roles_removed = change_role(nil, reason, :demote)
    # Rmove all the stafftools actions/controller access control rules for this user.
    stafftools_roles.destroy_all if roles_removed
    roles_removed
  end

  # Updates the user's role (site admin, developer).
  #
  # role   - The new role to give the user.
  # reason - A String explanation for why/how the user was updated. Required.
  # action - The action to instrument (grant_site_admin).
  #
  # Returns false if no reason was provided, true otherwise.
  def change_role(role, reason, action)
    return false if reason.blank?

    update_attribute(:gh_role, role)
    instrument(action, reason: reason)
    true
  end

  # Unlock a repository.
  #
  # repo - the repository to be unlocked
  # reason - internal reason for the unlock -- if none given, the reason will be pulled
  # => from the active staff access grant
  #
  # Returns the RepositoryUnlock object if successful, false if not.
  def unlock_repository(repo, reason = nil)
    if can_unlock_repos?(repository: repo)
      if grant = repo.active_staff_access_grant
        clear_cached_unlocked_repository(repo)
        return RepositoryUnlock.create_unlock(self, repo, grant.reason, grant)
      elsif GitHub.enterprise?
        clear_cached_unlocked_repository(repo)
        if unlock = RepositoryUnlock.create_unlock(self, repo, reason)
          instrument_repo_unlock(unlock) unless enterprise_admin_unlocking_repo?
          return unlock
        end
      elsif can_unlock_user_repo?(repository: repo)
        reason = "Enterprise user enabled temporary access to user-owned repo"
        clear_cached_unlocked_repository(repo)
        if unlock = RepositoryUnlock.create_unlock(self, repo, reason)
          notify_repo_owner_on_unlock(unlock)
          instrument_repo_unlock(unlock)
          return unlock
        end
      end
    end

    false
  end

  # Has this user unlocked a given repository?
  #
  # Returns a boolean
  def has_unlocked_repository?(repo)
    async_has_unlocked_repository?(repo).sync
  end

  def async_has_unlocked_repository?(repo)
    unless defined?(@async_has_unlocked_repository)
      @async_has_unlocked_repository = Hash.new do |hash, repo|
        hash[repo] = Platform::Loaders::UnlockedRepositoryCheck.load(self, repo.id)
      end
    end

    @async_has_unlocked_repository[repo]
  end

  private

  def clear_cached_unlocked_repository(repo)
    @async_has_unlocked_repository.delete(repo) if defined?(@async_has_unlocked_repository)
  end

  def instrument_repo_unlock(unlock)
    GitHub.instrument \
      "repo.temporary_access_granted",
      user: unlock.repository.owner,
      actor: unlock.unlocked_by,
      repo: unlock.repository,
      reason: unlock.reason
  end

  def notify_repo_owner_on_unlock(repo_unlock)
    unlocked_by = repo_unlock.unlocked_by
    repository = repo_unlock.repository
    repo_owner = repository.owner
    return unless repo_owner.is_a?(User)

    business = repo_owner.enterprise_managed_business
    return if business.nil?

    EnterpriseManagedUserMailer.user_repository_unlocked(business, repo_owner, unlocked_by, repository).deliver_later
  end

  # Private: Used to check if this user is a member of the gh_role 'staff', but
  # not an employee - except when that's not required to be staff.
  #
  # Returns true if the user is staff but not an employee when they should be.
  def is_staff_but_not_employee?
    has_staff_role? && GitHub.require_employee_for_site_admin? && !employee_ignoring_override?
  end

  # Private: Used to enforce that a staff user is also an employee if
  # someone on the console attempts to force the issue with update_attribute.
  #
  # Raises an ArgumentError if this user is not an employee; and that
  # enforcement is appropriate.
  def staff_must_be_an_employee!
    if is_staff_but_not_employee?
      raise ArgumentError, "Staff must also be on the employees team."
    end
  end

  # Private: Custom validation method to prevent accidentally creating staff
  # who are not employees from the console.
  def staff_must_be_an_employee
    if is_staff_but_not_employee?
      errors.add(:gh_role, "staff must also be on the employees team. If this is you, try toggling staff mode with the ` key.")
    end
  end
end
