# typed: true
# frozen_string_literal: true

class RepositoryInvitation < ApplicationRecord::Domain::Repositories

  # Raised when a non-admin attempts to set a permission
  class InsufficientAbilities < ArgumentError; end

  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  destroy_in_background_with :repository

  belongs_to :invitee, foreign_key: "invitee_id", class_name: "User" # rubocop:todo Rails/InverseOf
  belongs_to :inviter, foreign_key: "inviter_id", class_name: "User" # rubocop:todo Rails/InverseOf
  belongs_to :role, foreign_key: "role_id", class_name: "Role" # rubocop:todo Rails/InverseOf

  has_one :sponsorship_repository, ->(invitation) {
    # `for_repository` returns generic `ActiveRecord::Relation` and sorbet doesn't know about `for_sponsor`
    T.unsafe(unscope(:where).for_repository(invitation.repository_id))
      .for_sponsor(invitation.invitee_id)
      .for_sponsorable(invitation.inviter_id)
  }

  validates_uniqueness_of :invitee_id, scope: :repository_id, allow_blank: true, allow_nil: true
  validates_uniqueness_of :email, scope: :repository_id, allow_blank: true, allow_nil: true, case_sensitive: false
  validates_length_of :email, within: 3..100, allow_blank: true
  validates_format_of :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_blank: true
  validates :repository_id, :inviter_id, presence: true
  validate :email_must_be_exclusive
  validate :email_must_not_be_prefixed
  validate :trade_controls_restrictions, on: :create
  validate :rate_limit_not_exceeded
  validate :must_be_org_to_use_roles

  before_validation :generate_token, on: :create, if: :email?
  after_create_commit :instrument_creation # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :clean_up_notifications_after_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :snapshot_license_state # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_business_license_usage # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  delegate :target_for_conditional_access, to: :repository

  enum :permissions, { read: 0, write: 1, admin: 2, triage: 3, maintain: 4 }

  INVITATION_UPDATE_BATCH_SIZE = 100
  PERMISSIONS = {
    "pull"  => :read,
    "push"  => :write,
    "admin" => :admin,
    "triage" => :triage,
    "maintain" => :maintain,
  }

  extend GitHub::Encoding
  force_utf8_encoding :hashed_token

  scope :for_invitee, ->(invitee_or_id) { where(invitee_id: invitee_or_id) }
  scope :for_repository, ->(repository_or_id) { where(repository_id: repository_or_id) }

  scope :excluding_expired, -> do
    where(created_at: GitHub.invitation_expiry_period.days.ago..)
  end

  scope :recently_expired, -> do
    where("created_at > ? AND created_at < ?",
      GitHub.invitation_expiry_cutoff.days.ago, GitHub.invitation_expiry_period.days.ago)
  end

  # TODO: modify to follow convention (explicit table clause seems strange)
  scope :all_expired, -> do
    where("repository_invitations.created_at < ?",
      GitHub.invitation_expiry_period.days.ago)
  end

  # Invite a user to a repository, unless they already belong to the organization
  #
  # invitee  - The user to add as a collaborator to this repository.
  # inviter  - The user who is adding the addee as a collaborator.
  # repository - The specified repository.
  # action - The level of permissions the collaborator will have
  # ignore_rate_limit - Whether the rate limit should be ignored when creating this invitation
  #
  # Returns a Hash with
  #   - success
  #   - if successful, invitation Invitation
  #   - if unsuccessful, errors String
  def self.invite_to_repo(invitee, inviter, repository, action: :write, ignore_rate_limit: false)
    org = repository.organization
    member_belongs_to_same_org = org && org.find_direct_or_team_member_by_login(invitee.login)

    # EMU users are added directly and not by invite, so we should never end up here.
    # https://github.com/github/external-identities/issues/888
    # https://github.com/github/repos/issues/10357
    if invitee.is_enterprise_managed?
      message = "Enterprise Managed Users cannot be invited to this repository because this Enterprise uses personal accounts."
      repository.errors.add(:base, :inviting_emu, message: message)
      return { success: false, errors: repository.errors }
    end

    if message = cannot_invite_because_outside_collaborator?(org, inviter, repository, member_belongs_to_same_org)
      repository.errors.add(:base, :inviting_outside_collaborators, message: message)
      return { success: false, errors: repository.errors }
    end

    if cannot_invite_because_fork_and_not_in_business?(org, repository, invitee)
      verb = GitHub.repo_invites_enabled? ? "invited" : "added"
      message = "Users outside of the enterprise account cannot be #{verb} to a private or internal fork"
      repository.errors.add(:base, :inviting_user_outside_of_business, message: message)
      return { success: false, errors: repository.errors }
    end

    invite_response = if !GitHub.repo_invites_enabled? || member_belongs_to_same_org
      # No neeed to ignore rate limit in this case because an invitation is not created
      invite_to_repo_without_confirmation(invitee, inviter, repository, action: action)
    else
      invite_to_repo_with_confirmation(invitee, inviter, repository, action: action, ignore_rate_limit: ignore_rate_limit)
    end

    invitation = invite_response[:invitation]
    if invite_response[:success] && invitation
      invitation.bundled_license_assignments.each do |assignment|
        assignment.touch
        Licensing::SendVssStatusMessageJob.perform_later(assignment: assignment)
      end
    end

    invite_response
  end

  def self.invite_to_repo_with_confirmation(invitee, inviter, repository, action: :write, ignore_rate_limit: false)
    # check_2fa false b/c admin should be able to send invite regardless, invitee will be prompted to enable 2FA on confirmation
    return { success: false, errors: repository.errors } unless repository.can_add_user?(invitee, inviter, check_2fa: false)

    # some invitations will have a custom role
    role_id, permission = fetch_role_and_permission(action, repository)

    invitation = RepositoryInvitation.new(
      repository_id: repository.id,
      inviter_id: inviter.id,
      invitee_id: invitee.id,
      permissions: permission,
      role_id: role_id
    )
    invitation.ignore_rate_limit = ignore_rate_limit
    invitation.save!

    RepositoryCollabInvitationJob.perform_later(invitation.id)
    { success: true, invitation: invitation }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, errors: e.record.errors }
  rescue ActiveRecord::RecordNotUnique => e
    invitation&.errors.add(:invitee_id, :taken)
    { success: false, errors: invitation&.errors }
  end

  # Use case: enterprise mode, or when the invitee belongs to the repo's org
  # Invite a user to a repository and skip the step involving the invitee
  # manually accepting or rejecting the invitation.
  #
  # invitee  - The user to add as a collaborator to this repository.
  # inviter  - The user who is adding the addee as a collaborator.
  # repository - The specified repository.
  #
  # Returns hash with a :success key.
  def self.invite_to_repo_without_confirmation(invitee, inviter, repository, action: :write)
    if repository.can_add_user?(invitee, inviter)
      repository.add_member_without_validation_or_notifications(
        invitee,
        inviter,
        action: action,
      )

      response = GitHub.newsies.auto_subscribe(invitee, repository)
      GitHub.newsies.async_auto_subscribe(invitee, [repository.id]) if response.failed?
      { success: true }
    else
      { success: false, errors: repository.errors }
    end
  end

  def self.invite_to_repo_by_email(email, inviter, repository, action: :write)
    return { success: false, errors: repository.errors } unless can_invite_with_email?(repository, inviter)

    existing_email = UserEmail.find_by(email: email)
    return invite_to_repo(existing_email.user, inviter, repository, action: action) if existing_email&.verified?

    previous_invitation = RepositoryInvitation.find_by(email: email, repository: repository)

    if previous_invitation.present?
      invitation = previous_invitation
    else
      # some invitations will have a custom role
      role_id, permission = fetch_role_and_permission(action, repository)

      invitation = RepositoryInvitation.create!(
        repository_id: repository.id,
        inviter: inviter,
        email: email,
        permissions: permission,
        role_id: role_id
      )

      invitation.bundled_license_assignments.each do |assignment|
        assignment.touch
        Licensing::SendVssStatusMessageJob.perform_later(assignment: assignment)
      end
    end

    RepositoryMailer.collab_invited(invitation).deliver_later

    { success: true, invitation: invitation }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, errors: e.record.errors }
  end

  # Can we invite a user through email to the repo?
  def self.can_invite_with_email?(repository, inviter)
    owner = repository.owner

    if owner.organization?
      if error = cannot_invite_because_outside_collaborator?(owner, inviter, repository, false)
        repository.errors.add(:base, error)
        return false
      end

      if repository.private? && owner.at_seat_limit?
        if owner.member?(inviter)
          repository.errors.add(:seat_limit, "You must purchase at least one more seat to invite this user as a collaborator.")
        else  # if the inviter is an outside collaborator with admin prvileges over this repo, don't tell them about the organization's seat count.
          repository.errors.add(:base, "Unable to invite user as a collaborator.")
        end

        return false
      end
    else
      if repository.private? && repository.at_seat_limit?
        repository.errors.add(:base, "You must upgrade your account to add more collaborators.")
        return false
      end
    end

    true
  end

  def self.permission_by_name_or_label(text)
    permissions[text] || permissions[PERMISSIONS[text]]
  end

  # Returns an error message string if the inviter cannot, otherwise returns false
  def self.cannot_invite_because_outside_collaborator?(org, inviter, repo, member_belongs_to_same_org)
    # return early if the check doesn't apply
    return false unless org && !member_belongs_to_same_org
    OutsideCollabCheck.new(org: org, inviter: inviter, repo: repo).cannot_invite?
  end

  # This class exists solely to give some names to the boolean checks we need to perform.
  class OutsideCollabCheck
    attr_reader :org, :inviter, :repo, :enterprise_admins_only

    def initialize(org:, inviter:, repo:)
      @org = org
      @inviter = inviter
      @repo = repo
      @enterprise_admins_only = org.enterprise_admins_only_can_invite_outside_collaborators?
    end

    # Returns false or a string representing the reason the given user/bot cannot invite outside collaborators
    def cannot_invite?
      if inviter.bot?
        bot_cannot_invite? && error_message
      else
        user_cannot_invite? && error_message
      end
    end

    private

    def error_message
      verb = GitHub.repo_invites_enabled? ? "invite" : "add"
      entity = enterprise_admins_only ? "enterprise" : "organization"
      collaborators = org.enterprise_managed_user_enabled? ? "repository collaborators" : "outside collaborators"

      "Only #{entity} owners can #{verb} #{collaborators}"
    end

    # For now, if outside collab invites are restricted to enterprise admins, no bots
    # can invite people.  Bot installations at the enterprise level are internal to GitHub only.
    def bot_cannot_invite?
      enterprise_admins_only || org_admin_bot_needed?
    end

    def org_admin_bot_needed?
      !org.resources.organization_administration.writable_by?(inviter) &&
        !repo.resources.administration.writable_by?(inviter)
    end

    def user_cannot_invite?
      if enterprise_admins_only && org_has_business?
        enterprise_admin_needed?
      else
        org_admin_needed?
      end
    end

    def org_admin_needed?
      !org.members_can_invite_outside_collaborators? &&
        !org.resources.organization_administration.writable_by?(inviter)
    end

    def enterprise_admin_needed?
      !org.business.resources.enterprise_administration.writable_by?(inviter)
    end

    def org_has_business?
      org.business.present?
    end
  end

  # To be added as a collaborator to an internal fork, invitee must be in the business
  # or must be a collaborator on the root.
  #
  # Returns true if we cannot invite the user for this reason.
  def self.cannot_invite_because_fork_and_not_in_business?(org, repo, invitee)
    private_business_fork = FeatureFlag.vexi.enabled?("no_collab_on_private_fork", default: false) ? (repo.private_fork? && repo.root.owner.business) : false
    return unless repo.internal_fork? || private_business_fork

    business = repo.root.owner.business

    invitee_in_business = invitee.business_ids.include?(business.id)
    invitee_collaborator_on_root = repo.root.members(actor_ids: invitee.id).any?

    return true unless invitee_in_business || invitee_collaborator_on_root

    false
  end

  scope :with_roles, ->(role_ids) {
    where(role_id: Array(role_ids))
  }

  def self.cancel_all_invitations_involving(repo_ids:, user:)
    involving(repo_ids, user).each do |invitation|
      invitation.cancel!(actor: user, force: true)
    end
  end

  def self.involving(repo_ids, user)
    repo_ids = Array(repo_ids)
    RepositoryInvitation.where(inviter_id: user.id).or(RepositoryInvitation.where(invitee_id: user.id)).
      filter { |invitation| repo_ids.include?(invitation.repository_id) }
  end

  # Public: Fetch the hash to use for server-side persistence of the given
  # token.
  #
  # token - A string.
  #
  # Returns the hashed base64 String.
  def self.digest_token(token)
    return nil unless token.present?

    Digest::SHA256.base64digest(token.to_s)
  end

  # Public: see if the given action is for the same role/permission as this invitation. Compare
  # actions by comparing the permission and the role_id. System roles don't use role_id, only
  # permission. Custom roles and triage/maintain use both.
  #
  # action     - action to compare
  #
  # Returns: Boolean
  def same_action?(action:)
    # retrieve role_id if it's a custom role, or a permission value otherwise
    action_role_id, action_permission =
      RepositoryInvitation.fetch_role_and_permission(action, repository, default_permission: nil)

    return false if action_role_id.nil? && action_permission.nil?

    # if the action is for a custom role, the invitation must be for the same role
    return role_id == action_role_id if action_role_id.present?

    # if it's not a custom role, see if the action's corresponding permission matches the
    # invitation's permission. If the invitation is based on a non-custom role, use the role's
    # name in place of the permission.
    invitation_permission = permissions
    invitation_permission ||= role&.name if role.present? && !role&.custom?
    RepositoryInvitation.permissions[invitation_permission] == action_permission
  end

  # Add a user to the repository after they have accepted an invitation.
  #
  # Returns boolean.
  def accept!(acceptor: invitee)
    # Don't allow invitations to be accepted if the invite has expired. Delete the invitation
    if invite_expired?
      self.destroy
      return false
    end

    # Email invitations don't have an invitee stored, and can be
    # accepted by any user with the correct token. For regular invitations,
    # we need to make sure the acceptor and the invitee are the same.
    unless email?
      return false unless acceptor == invitee
    end

    return unless repository&.can_add_user?(acceptor, inviter, already_invited: true)

    action =
      if role
        role&.name
      else
        self.permissions || :read
      end

    # We have to have a check here since adding the user to the repository makes them an outside collaborator.
    adding_outside_collaborator = repository&.organization.present? &&
      invitee.present? &&
      !T.must(repository&.organization).members.include?(invitee) &&
      !T.must(repository&.organization).user_is_outside_collaborator?(invitee&.id)

    self.repository&.add_member_without_validation_or_notifications(
      acceptor,
      inviter,
      action: action,
    )

    assign_user_to_bundled_license_assignment(acceptor)

    instrument_acceptance
    instrument_acceptance_for_organization if adding_outside_collaborator
    response = GitHub.newsies.auto_subscribe(acceptor, repository)
    GitHub.newsies.async_auto_subscribe(acceptor, [repository_id]) if response.failed?
    self.destroy
    self.destroyed?
  end

  # Clean up the invitation after a user declines an invitation.
  #
  # Returns boolean.
  def reject!
    instrument_rejection
    bundled_license_assignments.each do |assignment|
      assignment.touch
      Licensing::SendVssStatusMessageJob.perform_later(event_type: :declined_repo_invite, assignment: assignment)
    end
    self.destroy
    self.destroyed?
  end

  # Cancel the invitation.
  #
  # actor - The user that is cancelling the invitation.
  # force - force the invitation cancellation
  #
  # Returns a Boolean.
  def cancel!(actor:, force: false)
    return false unless repository&.adminable_by?(actor) || force
    instrument_cancellation(actor: actor)
    with_write { self.destroy }
    self.destroyed?
  end

  # Enqueue a job to cancel the invitation.
  #
  # actor - The user that is cancelling the invitation.
  # permit_non_repo_admins - Boolean indicating whether actors that are not repository
  # admins should be able to cancel the invitation. Defaults to false.
  #
  # Returns nothing.
  def enqueue_cancel_invitation(actor:, permit_non_repo_admins: false)
    CancelRepoInvitationJob.perform_later \
      actor: actor,
      invitation: self,
      permit_non_repo_admins: permit_non_repo_admins
  end

  def event_payload
    {
      repo_invitation_id: self.id,
      inviter: inviter,
      invitee: invitee,
      repo: repository,
      org: repository&.organization,
      business: repository&.business,
    }
  end

  def hydro_payload
    {
      actor: inviter,
      invitee: invitee,
      repository: repository,
    }
  end

  def instrument_creation
    role_name = role ? "custom_role" : permissions
    GitHub.dogstats.increment("repository_invitation", tags: ["action:create", "role:#{role_name}"])
    GlobalInstrumenter.instrument "repository.invite", hydro_payload
    instrument(:create)
  end

  def instrument_acceptance
    GitHub.dogstats.increment("repository_invitation", tags: ["action:accept"])
    instrument(:accept)
  end

  def instrument_acceptance_for_organization
    return if invitee.nil? || repository&.organization.nil?
    GitHub.instrument"org.add_outside_collaborator", {
      inviter: inviter&.login,
      inviter_id: inviter&.id,
      org: repository&.organization&.login,
      org_id: repository&.organization&.id,
      repo: repository&.name,
      repo_id: repository&.id,
      public_repo: repository&.public?,
      permission: permission_string,
      invitee: invitee&.login,
      invitee_id: invitee&.id,
      invitation_email: invitee&.email,
    }
  end

  def instrument_rejection
    GitHub.dogstats.increment("repository_invitation", tags: ["action:reject"])
    instrument(:reject)
  end

  def instrument_cancellation(actor:)
    instrument(:cancel, event_payload.merge(actor: actor))
  end

  def mark_read
    response = GitHub.newsies.web.rollup_summary_from_repository_invitation(self)
    if response.success?
      response = GitHub.newsies.web.mark_summary_read(self.invitee, response.value)
    end
    response
  end

  # Public: Generate a link to this invitation
  #
  # Will append a token to the URL if one is present. A token is only present
  # on the invitation if the invitation is for an email address. If the invitation
  # is for a particular user with a username, the token will not be present.
  #
  # Returns a String.
  def permalink
    return unless self.repository
    link = "#{self.repository&.permalink}/invitations"
    link += "?invitation_token=#{self.token}" if self.token.present?
    link
  end

  def permission_string
    if role
      role&.name
    else
      self.permissions || "write"
    end
  end

  # Public: Enqueue a jobs to update `batch_size` invitations at a time.
  #
  # invitations   - The invitations to be updated.
  # setter        - The user that is updating the invitation.
  # action        - The permission or role invitation is being updated to.
  # role          - Custom role (default: nil)
  # batch_size    - Batch size to be passed processed.
  #
  def self.batch_enqueue_update_repo_permissions(invitations:, setter:, action:, role: nil, batch_size: INVITATION_UPDATE_BATCH_SIZE)
    invitations.each_slice(batch_size) do |invitations_slice|
      BatchUpdateInvitationRepoPermissionsJob.perform_later(invitations_slice, action: action, setter: setter, role: role)
    end
  end

  def enqueue_update_repo_permissions(setter:, action:)
    ability = evaluate_ability(action, repository)
    UpdateInvitationRepoPermissionsJob.perform_later(self, action: ability, setter: setter)
  end

  def evaluate_ability(action, repository)
    ability =
      if RepositoryRole.custom_role_by_name(action, owner: repository.owner)
        action
      else
        permission_to_ability(action)
      end

    raise ArgumentError, "Invalid permission #{action}" if ability.nil?
    ability
  end

  # Public: Update permissions on the invitation.
  #
  # permission - The permission the invitation is being updated to.
  #              Can be :read, :write, :admin, :triage, :maintain, or a custom role.
  # setter     - The User that is updating the invitation.
  #
  # Returns Boolean
  def set_permissions(permission, setter)
    raise ArgumentError, "setter is required!" unless setter
    unless T.must(repository).resources.administration.writable_by?(setter)
      raise InsufficientAbilities, "#{setter.inspect} lacks the ability to set #{permission.inspect}"
    end

    # if a custom role is present, we want to clear out the old permission and set the role_id
    # if switching to an enum permission from a custom role, we need to clear out the old role_id
    if role = RepositoryRole.custom_role_by_name(permission, owner: repository&.owner)
      update(permissions: nil, role_id: role.id)
    else
      action = permission_to_ability(permission)
      raise ArgumentError, "Invalid permission #{permission}" if action.nil?
      update(permissions: action, role_id: nil)
    end
  end

  def summary
    "Invitation to join #{self.repository&.name_with_owner} from #{self.inviter&.login}"
  end

  def notifications_thread
    self
  end

  def notifications_list
    self.repository
  end

  def notifications_author
    self.inviter
  end

  def async_readable_by?(actor)
    return Promise.resolve(false) unless actor

    async_repository.then do |repo|
      next false unless repo

      repo_readable = false
      # Method visible_and_readable_by? checks for invitation use-cases but doesn't work with installations
      # That's why we use readable_by? for IntegrationInstallation admin use-case
      # (admin should have access to everything by default)
      if actor.is_a? IntegrationInstallation
        repo_readable = repo.readable_by?(actor)
      else
        repo_readable = repo.visible_and_readable_by?(actor)
      end

      if repo_readable && invitee_id == actor.id && !actor.can_have_granular_permissions?
        next true
      end

      repo.resources.administration.readable_by?(actor)
    end
  end

  # Public: Determine if the Invitation is readable
  # by a given actor.
  #
  # - The invitee can see their own invitation
  # - Any actor who can admin the repository can see
  #   the invitation
  # - Any IntegrationInstallation with
  #   { "administration" => :read } on the parent
  #   repository
  #
  # Returns a Boolean.
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Checks whether the invite is older than the set expiry period
  #
  # Returns boolean
  def invite_expired?
    if created_at&.before?(GitHub.invitation_expiry_period.days.ago)
      can_expire?
    else
      false
    end
  end

  # Public: Get the reason the invitation failed, otherwise nil.
  #
  # Returns String.
  def failed_reason
    return unless invite_expired?

    # Expiry is currently the only failure mode.
    "expired"
  end

  # Public: Get the reason describing the failure if the invitation failed, otherwise nil.
  #
  # Returns String.
  def failed_reason_description
    return unless invite_expired?

    # Expiry is currently the only failure mode.
    "Invitation expired. User did not accept this invite for #{GitHub.invitation_expiry_period} days"
  end

  # Public: Stores the raw token in-memory so it's available for the duration of
  # the request. Stores a hash of the token in the database to be used to lookup
  # invitations by token.
  #
  # Returns the set token.
  def token=(token_value)
    self.hashed_token = RepositoryInvitation.digest_token(token_value.to_s)
    @token = token_value
  end
  attr_reader :token

  # Public: Finds an invitation matching the supplied token.
  #
  # token   - The token String generated by the RepositoryInvitation.
  #
  # Returns an RepositoryInvitation or nil if the invitation could not be
  # found.
  def self.find_by_token(token)  # rubocop:disable GitHub/FindByDef
    return nil unless token.present?
    where(hashed_token: digest_token(token)).first
  end

  # Public: Resets the token and saves the invitation. Since token is only stored
  # in-memory, this is needed to regenerate links for an inviation (e.g. to resend
  # and invitation email)
  #
  # Returns a Boolean indicating if the reset was successful.
  def reset_token
    return false unless email?

    generate_token && with_write { save }
  end

  # Public: The String representation of the OrganizationInvitation. If the
  # invitation is for a user it will return the user's login. If the
  # invitation is for an email invitation it will return the email.
  #
  # Returns String.
  def email_or_invitee_login
    if email?
      email
    else
      invitee&.login
    end
  end

  def business
    return @business if defined? @business
    return nil if repository&.owner&.business.nil?
    @business = repository&.owner&.business
  end

  def bundled_license_assignments
    return @bundled_license_assignments if defined? @bundled_license_assignments
    assignment_email = email? ? email : invitee&.email
    return [] unless business&.volume_licensing_enabled? && assignment_email
    @bundled_license_assignments = business.bundled_license_assignments.where(email: assignment_email)
  end

  scope :for_organization_ids, ->(organization_ids) {
    joins(:repository).where("repositories.organization_id": organization_ids)
  }

  # Public: return the role_id and the permission
  #
  # action      -   action to look up
  # repository  -   repository to check
  # default_permission - default permission to use, if action is not a custom role, but also
  #                      isn't a valid permission
  #
  # Returns: [role_id, permission]
  def self.fetch_role_and_permission(action, repository, default_permission: permissions[PERMISSIONS["push"]])
    role = RepositoryRole.custom_role_by_name(action, owner: repository.owner)

    permission = permission_by_name_or_label(action) || default_permission if role.nil?

    [role&.id, permission]
  end

  # Public: Set whether an unpersisted invitation can ignore the rate limit or not
  #
  # This should be used only on an unpersisted invitation since the rate limit validation only runs on create.
  def ignore_rate_limit=(value)
    raise "Can't ignore the rate limit on persisted invitations" if persisted?
    @ignore_rate_limit = value
  end

  # Public: Is this invitation one that has an expiration date, after which it can no longer be accepted?
  #
  # Returns a Boolean.
  def can_expire?
    # Repository invitations granted from a sponsorship never expire while the
    # sponsorship is still active
    !sponsors_only_repository_invitation? && !advisory_workspace_repository_invitation?
  end

  # Public: Is this invitation still valid because the invitee is still an active sponsor
  # at a Sponsors tier that grants access to the repository?
  #
  # Returns a Boolean.
  def sponsors_only_repository_invitation?
    return false unless GitHub.sponsors_enabled?

    # A `sponsorship_repository` will only exist when the sponsorship is still active:
    sponsorship_repository.present?
  end

  # Public: Is this invitation still valid because the invitee is still an active collaborator
  # on the advisory that grants access to the repository?
  #
  # Returns a Boolean.
  def advisory_workspace_repository_invitation?
    return false unless GitHub.repository_advisories_enabled?

    repository&.parent_advisory&.writable_by?(invitee)
  end

  def rate_limit_not_exceeded?
    return true if ignore_rate_limit?
    return true unless GitHub.rate_limiting_enabled?
    return true unless repository.present?
    return true if RepositoryInvitationRateLimitOverride.overridden?(repository_id)

    # Ignore rate limit when inviting members from the repo's owning organization:
    return true if repository&.organization && T.must(repository&.organization).members(actor_ids: invitee_id).any?

    return false if exceeded_rate_limit?

    true
  end

  private

  # Private: Whether to ignore the rate limit when this invitation is created
  #
  # Set by calling `ignore_rate_limit=`
  #
  # Returns: Boolean
  def ignore_rate_limit?
    !!@ignore_rate_limit
  end

  def clean_up_notifications_after_destroy
    # in rare cases invitee may already have been deleted
    return if !self.invitee

    list = Newsies::List.new("Repository", repository_id)
    thread = Newsies::Thread.to_object(self)
    summary_response = GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
    if summary_response.success?
      summary = summary_response.value
      GitHub.newsies.web.delete(self.invitee, summary) if summary
    end
  end

  def outstanding_invitations_in_past_24_hours
    RepositoryInvitation.where("repository_id = ? AND created_at >= ?", self.repository_id, Time.zone.now - 24.hours)
  end

  def rate_limit_not_exceeded
    if !rate_limit_not_exceeded?
      GitHub.dogstats.increment "repository_invitations.rate_limit_exceeded"
      errors.add(:rate_limit, "exceeded")
    end
  end

  def exceeded_rate_limit?
    outstanding_invitations_in_past_24_hours.count >= GitHub.repository_invitation_rate_limit
  end

  def must_be_org_to_use_roles
    return unless repository.present?
    return unless permissions.to_s == "triage" || permissions.to_s == "maintain"
    owner = repository&.owner
    unless owner&.organization?
      errors.add(:permissions, "is invalid")
    end
  end

  def trade_controls_restrictions
    return unless repository.present?
    if repository&.trade_restricted?
      errors.add(:base, TradeControls::Notices.notice_as_plaintext(:org_invite_restricted))
      return false
    end
    true
  end

  def email_must_be_exclusive
    if !invitee_id? && !email?
      errors.add(:base, "invitee or email must be present")
    elsif invitee_id? && email?
      errors.add(:email, "invitee has already been set")
    end
  end

  def email_must_not_be_prefixed
    if email? && email&.start_with?("mailto:")
      errors.add(:email, "should not be prefixed")
    end
  end

  def snapshot_license_state
    return unless repository&.licensing_enabled?

    Licensing::SnapshotLicensesJob.perform_later(business)
  end

  def update_business_license_usage
    business&.update_license_usage
  end

  def assign_user_to_bundled_license_assignment(user)
    return unless business&.volume_licensing_enabled?

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_later(
      business: business, user: user, emails: [email].compact
    )
  end

  # Given a permission, it returns the symbol for the equivalent ability
  # if the input is already in ability format, it is a no_op
  # if the input is not a valid permission or ability, it returns nil
  def permission_to_ability(permission)
    return PERMISSIONS[permission.to_s] if PERMISSIONS.keys.include? permission.to_s
    permission.to_sym if PERMISSIONS.values.include? permission.to_sym
  end

  # Private: Generates the token used to lookup email invitations.
  def generate_token
    self.token = SecureRandom.hex(20)
  end
end
