# typed: true
# frozen_string_literal: true

class OrganizationInvitation < ApplicationRecord::Domain::Users

  include GitHub::Relay::GlobalIdentification

  SPAMMY_INVITEE_ERROR_MESSAGE = "You cannot accept this invitation because your account has been flagged. If you believe this is a mistake, please contact support."
  EMAIL_NOT_VERIFIED_ERROR_MESSAGE = "The email address that received this invitation does not match your GitHub account. Add the email address to your account or contact your organization owner with questions about next steps."
  PENDING_INVITATIONS_QUERY_LIMIT = 3000

  enum :role, {
    direct_member: 1,
    admin: 2,
    billing_manager: 3,
    hiring_manager: 4, # no longer used
    reinstate: 5,
  }

  enum :failed_reason, {
    no_more_seats: 1,
    trade_controls: 2,
    already_accepted: 3,
    invalid_generic: 4,
    expired: 5,
  }

  enum :invitation_source, {
    unknown: 0,
    member: 1,
    scim: 2
  }

  # Raised when someone accepts an already-accepted invitation.
  class AlreadyAcceptedError < StandardError; end

  # Raised when the user does not meet the requirements for Team that is part of the invite.
  class DoesNotMeetTeamRequirementsError < StandardError; end

  # Raised when someone attempts to create an invalid OrganizationInvitation.
  class InvalidError < StandardError; end

  # Raised when no seats are available to invite new members
  class NoAvailableSeatsError < StandardError; end

  # Raised when inviting a user with logins from a sanctioned country to a paid org
  class TradeControlsError < StandardError; end

  belongs_to :organization
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  has_many :team_invitations, dependent: :destroy
  has_many :teams, through: :team_invitations

  belongs_to :external_identity, inverse_of: :organization_invitation

  scope :pending, -> { where(accepted_at: nil, cancelled_at: nil, failed_at: nil) }

  scope :recently_expired, -> do
    pending.where("created_at > ? AND created_at < ? AND external_identity_id IS NULL",
      GitHub.invitation_expiry_cutoff.days.ago, GitHub.invitation_expiry_period.days.ago)
  end
  scope :excluding_expired, -> do
    where(created_at: GitHub.invitation_expiry_period.days.ago..).or(
      where.not(external_identity_id: nil)
    )
  end

  scope :failed, -> { where.not(failed_at: nil) }
  scope :with_business_role, -> (*roles) {
    where(role: OrganizationInvitation.roles.values_at(*roles))
  }
  scope :with_valid_role, -> { where(role: OrganizationInvitation.roles.values) }

  # Returns all organization invitations that don't have the given role(s).
  #
  # Takes any number of symbol role symbols
  scope :except_with_role, -> (*roles) {
    where("role NOT IN (?)", OrganizationInvitation.roles.values_at(*roles))
  }

  # Excludes records where the invitee is a spammy user unless the viewer is
  # staff.
  #
  # Includes invitations where the invitee is anonymous
  #
  # viewer - The User we are rendering the records for.
  #          Usually should be current_user. Accomodates viewer
  #          being nil/false for anonymous users.
  # show_spam_to_staff - Override the assumption that staff should
  #                      see spam by setting this to `false`.
  #                      Defaults to `true`.
  scope :filter_spam_for, lambda { |viewer, show_spam_to_staff: true|
    return if !GitHub.spamminess_check_enabled?

    # We don't filter anything for staff
    return if viewer.try(:site_admin?) && show_spam_to_staff

    invitation = arel_table
    user = User.arel_table

    joins(invitation.join(user, Arel::Nodes::OuterJoin).on(invitation[:invitee_id].eq(user[:id])).join_sources)
      .where(invitation[:invitee_id].eq(nil).or(user[:spammy].eq(false)))
  }

  scope :like_login_or_profile_name_or_email, -> (input) {
    left_joins(invitee: :profile)
      .where(["users.login LIKE :query OR profiles.name LIKE :query OR organization_invitations.email LIKE :query", { query: "%#{input}%" }])
  }

  scope :with_invitation_source, -> (invitation_source) {
    scope = where(invitation_source: OrganizationInvitation.invitation_sources.values_at(invitation_source))

    # backward compatibility with old SCIM invites that don't expire and thus don't have their source populated
    scope = scope.or(where("external_identity_id IS NOT NULL")) if invitation_source == :scim
    scope
  }

  scope :order_by_title, -> (sort_order) {
    sort_order = :asc if sort_order.nil?
    left_joins(invitee: :profile)
      .order(Arel.sql("COALESCE(profiles.name, users.login, organization_invitations.email) #{sort_order.to_s.upcase}"))
  }

  validates_length_of :email, within: 3..100, allow_blank: true
  validates_format_of :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_blank: true
  validates_presence_of :organization, :inviter
  validates :role, presence: true
  validates :hashed_token, presence: true, length: { is: 44 }, if: :email?
  validates :accepted_at, uniqueness: { scope: :normalized_email, message: "has already been accepted" }, allow_nil: true
  validate :inviter_must_not_be_blocked
  validate :email_must_be_exclusive, on: :create
  validate :invitee_must_not_be_opted_out
  validate :email_must_not_be_prefixed
  validate :org_must_not_be_spammy

  before_validation :generate_token, on: :create, if: :email?
  before_save  :set_failed_at, if: :failed?
  after_create :instrument_invite_member
  after_commit :send_invitation_email, on: :create
  after_commit :snapshot_license_state
  after_commit :update_business_license_usage

  extend GitHub::Encoding
  force_utf8_encoding :hashed_token

  def self.valid_role?(role)
    roles[role].present?
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

  # Public: Finds an invitation matching the supplied token. If called on an
  # ActiveRecord scope, the current scope is used to lookup the invitation.
  #
  # token   - The token String generated by the OrganizationInvitation.
  #
  # Returns an OrganizationInvitation or nil if the invitation could not be
  # found.
  def self.find_by_token(token)  # rubocop:disable GitHub/FindByDef
    return nil unless token.present?
    where(hashed_token: digest_token(token)).first
  end

  def self.with_normalized_email(email)
    where(normalized_email: UserEmail.normalize(email))
  end

  # Public: Returns all pending invitations belonging to an invitee, or any of
  # the invitee's verified UserEmail addresses or the email address supplied.
  #
  # invitee     - A User model. The owner of a pending invitation.
  # emails      - One or more email addresses to consider when searching for
  #               pending invitations.
  # include_private_emails - a Boolean indicating if we should return the private
  #                          email address for a user
  #
  # Returns an Array of pending organization invitations.
  def self.with_invitee_or_normalized_email(invitee: nil, emails: nil, include_private_emails: true)
    emails = UserEmail.safe_bulk_normalize(users: invitee, emails: emails, verified: true, include_private_emails: include_private_emails)
    return scoped unless invitee || emails.any?

    sql = Arel.sql("")

    if invitee.present?
      sql += Arel.sql scoped.where(invitee_id: invitee.id).to_sql

      if emails.any?
        sql += Arel.sql "UNION ALL #{scoped.where("normalized_email IN (:emails)").to_sql}",
          emails: emails
      end

      sql += Arel.sql "ORDER BY id DESC"
    else
      sql += Arel.sql <<-SQL, emails: emails
        #{scoped.where("normalized_email IN (:emails)").to_sql}
        ORDER BY id DESC
      SQL
    end

    self.find_by_sql(sql)
  end

  def send_invitation_email
    return if T.must(inviter).spammy? || failed?

    if billing_manager?
      OrganizationMailer.invited_to_billing_manager_role(self).deliver_later
    elsif email?
      known_user = User.find_by_email(email)
      if known_user.nil? || !known_user.blocking?(*T.must(organization).admins)
        AccountMailer.invited_to_org_by_email(self).deliver_later
      end
    else
      AccountMailer.invited_to_org(self).deliver_later
    end
  end

  def adminable_by?(user)
    T.must(organization).adminable_by?(user)
  end

  def failed?
    failed_reason.present?
  end

  def failed_reason_description
    return unless failed?

    case failed_reason
    when "no_more_seats"
      "No seats available"
    when "trade_controls"
      "This user isn't able to use this feature due to trade regulations"
    when "already_accepted"
      "Invitation already accepted"
    when "invalid_generic" # What?
      "Invitation is invalid"
    when "expired"
      "Invitation expired. User did not accept this invite for #{GitHub.invitation_expiry_period} days"
    else
      raise "Unhandled failed_reason: #{failed_reason.inspect}, add a `when` clause to OrganizationInvitation#failed_reason_description"
    end
  end

  def set_failed_at
    self.failed_at = Time.current
  end

  # Public: Is the invitation reinstating an outside collaborator to the organization
  #
  # This is true if:
  #   - Is the invitation is reinstating a user
  #   - Is there a corresponding restorable user
  #   - The user only has memberships in repositories (admins and direct members have organization memberships)
  #
  # Returns a boolean.
  def reinstating_outside_collaborator?
    return false unless reinstate?
    restorable_user = Restorable::OrganizationUser.restorable(organization, invitee)
    restorable_user.restorable? &&
    restorable_user.restorable.present? &&
    (restorable_user.restorable.memberships.map(&:subject_type) - ["Repository"]).empty?
  end

  # Public: Accept the invitation. This adds the invitee to the specified
  # organization and all specified teams.
  #
  # acceptor    - Optional User who is accepting the invitation. Used for email
  #               address invites. Defaults to the invitee.
  # via_email   - Optional flag to indicate the invitation was landed on from
  #               email and should be recorded as such. Defaults to false.
  #
  # Returns a AcceptInvitationStatus.
  def accept(acceptor: invitee, via_email: false)
    # fresh_accepted? is required here to avoid a race condition:
    # https://github.com/github/github/issues/104510
    return AcceptInvitationStatus::ALREADY_ACCEPTED if fresh_accepted?

    return AcceptInvitationStatus::INVALID_ACCEPTOR unless email? || (acceptor == invitee)

    if prevented_by_trade_controls_restrictions?
      return AcceptInvitationStatus::TRADE_CONTROLS_RESTRICTED
    end

    organization = T.must(self.organization)
    # Don't allow invitations to be accepted if the acceptor is blocked.
    return AcceptInvitationStatus::BLOCKED if organization.blocking?(acceptor)

    # Don't allow invitations to be accepted if the invite has expired
    if invite_expired?
      expire if failed_at.nil?
      return AcceptInvitationStatus::EXPIRED
    end

    if acceptor_needs_to_verify_email?(acceptor: acceptor)
      return AcceptInvitationStatus::EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER
    end

    if organization.org_invite_email_verification_enabled? && acceptor.spammy?
      return AcceptInvitationStatus::SPAMMY_INVITEE
    end

    return OrganizationInvitation::AcceptInvitationStatus::NO_2FA unless organization.two_factor_requirement_met_by?(acceptor)

    # re:lock_two_factor, see https://github.com/github/github/issues/116372
    acceptor.lock_two_factor do
      record_accept_metrics(via_email: via_email) do

        if external_identity && identity = ExternalIdentity.by_provider(T.must(external_identity).provider).linked_to(acceptor).first
          return AcceptInvitationStatus::USER_ALREADY_LINKED if identity.id != T.must(external_identity).id
        end

        Ability.transaction do
          # We record the creator of the invitation as the actor, even though the
          # receiver of the invitation is the one logged-in and accepting it.
          # We need to nil out actor_ip, since we don't want to record the
          # logged-in user (the invitee) as the actor, and we don't know the
          # inviter's IP.
          GitHub.context.push(actor_ip: nil) do
            Audit.context.push(actor_ip: nil) do
              add_user_to_organization(acceptor)
              instrument_accept_invite

              Deduplicator.call!(invitation: self, acceptor: acceptor)

              team_invitations.includes(:team).each do |team_invitation|
                # destroy invitation if the team in the invitation is managed through group-syncer
                if team_invitation.team.externally_managed?
                  team_invitation.destroy
                  next
                end

                team_status = team_invitation.team.add_member(acceptor, adder: team_invitation.inviter, skip_organization_seat_checks: true)

                if team_status.error?
                  GitHub.logger.error(
                    exception: DoesNotMeetTeamRequirementsError.new(team_status.message),
                    "gh.team.status": team_status.status,
                    "enduser.id": acceptor.to_s,
                    "gh.team_invitation.inviter": team_invitation.inviter.to_s,
                  )
                  raise DoesNotMeetTeamRequirementsError, team_status.message
                elsif team_invitation.maintainer?
                  begin
                    team_invitation.team.promote_maintainer(acceptor)
                  rescue Organization::AbilityDependency::DirectMemberRequiredError
                    # If someone tried to invite a non-org-member as a team maintainer
                    # silently bail out rather than blowing up the invitation
                  end
                end
              end
              link_external_identity(user: acceptor)
            end
          end

          # We need to do a fresh check again before setting accepted_at in order to avoid a race
          # condition where multiple accounts can ride in on one invitation.
          if fresh_accepted?
            AcceptInvitationStatus::ALREADY_ACCEPTED
          else
            touch :accepted_at

            AcceptInvitationStatus::SUCCESS
          end
        end
      rescue DoesNotMeetTeamRequirementsError => e
        OrganizationInvitation::AcceptInvitationStatus.new(:does_not_meet_team_requirements, e.message)
      end
    end
  end

  # Public: Has the invitation been accepted?
  #
  # Returns a boolean.
  def accepted?
    accepted_at?
  end

  # Public: Has the invitation been accepted? This differs from the normal #accepted_at?
  # in that it always gets the fresh value through requerying. GitHubSQL is used to bypass
  # activerecord for speed. This is primarily used for solving a race condition with invitations.
  #
  # Returns Boolean
  def fresh_accepted?
    value = self.class.connection.select_value(Arel.sql(<<-SQL, id: self.id))
      SELECT accepted_at FROM organization_invitations WHERE id = :id
    SQL

    !value.nil?
  end

  # Public: Is the invitation pending?
  #
  # Returns a boolean.
  def pending?
    !accepted? && !cancelled? && !failed?
  end

  # Public: Is the invitation cancelled?
  #
  # Returns a boolean
  def cancelled?
    cancelled_at?
  end

  # Public: Add the specified team to the invitation.
  #
  # team    - The team to add to the invitation.
  # inviter - The person adding the team to the invitation.
  # role    - The role to invite the user to the team as. Use :member for a
  #           regular team member and :maintainer for a team maintainer.
  #           Defaults to :member.
  #
  # Returns nothing.
  def add_team(team, inviter:, role: :member)
    raise ArgumentError, "invalid TeamInvitation role" unless TeamInvitation.valid_role?(role)

    team_invitation         = team_invitation_for(team) || team_invitations.build
    team_invitation.team    = team
    team_invitation.inviter = inviter
    team_invitation.role    = role

    team_invitation.save!

    reload
  end

  # Public: Cancel the invitation.
  #
  # actor - User that is cancelling the invitation.
  # notify - Boolean indicating whether we should send an email to the invitee upon cancellation.
  # instrument - Should we instrument this action? The only scenario in which
  # this is false is when we are silently cancelling duplicates
  #
  # Returns nothing.
  def cancel(actor:, notify: true, instrument: true)
    raise AlreadyAcceptedError, "can't cancel an accepted invitation" if accepted?

    GitHub.dogstats.distribution_time("organization_invitation.time", tags: ["action:cancel"]) do
      instrument_cancel_invite(actor: actor) if instrument

      with_write { touch(:cancelled_at) } if persisted?

      bundled_license_assignments.each do |assignment|
        with_write { assignment.touch }
        Licensing::SendVssStatusMessageJob.perform_later(event_type: :declined_org_invite, assignment: assignment)
      end

      if reinstate?
        GitHub.dogstats.increment("organization_invitation", tags: ["action:cancel", "reinstate:true"])
      else
        GitHub.dogstats.increment("organization_invitation", tags: ["action:cancel", "reinstate:false"])
      end

      if !billing_manager? && notify && !inviter&.spammy?
        AccountMailer.org_invitation_canceled(self).deliver_later
      end
    end
  end

  # Public: Can the specified user cancel the specified invitation?
  #
  # canceler - The user trying to cancel the invitation.
  #
  # Returns a boolean.
  def cancelable_by?(canceler)
    return true if canceler == invitee || actor_can_cancel_email_invite?(actor: canceler)
    organization = T.must(self.organization)
    if canceler.can_have_granular_permissions?
      organization.resources.members.writable_by?(canceler)
    else
      organization.adminable_by?(canceler) || organization.business&.adminable_by?(canceler)
    end
  end

  # Public: Is the specified team a part of this invitation?
  #
  # team - Team to check if this invitation includes.
  #
  # Returns a boolean.
  def includes_team?(team)
    team_invitation_for(team).present?
  end

  # Public: Remove the specified team from the invitation. If there are no more
  # teams on the invitation afterwards, it will be canceled.
  #
  # Fails silently if the specified team is not on the invitation.
  #
  # team - Team to remove from the invitation.
  #
  # Returns nothing.
  def remove_team(team)
    team_invitations.where(team_id: team).each(&:destroy)
  end

  # Public: Should the inviter be shown to users?
  #
  # This will be false if:
  #   - the inviter is the same as the organization that this
  #     invitation is for (which is probably the result of an org transform). It
  #   - there's no inviter (which can happen if the inviter
  #     is deleted after sending the invitation).
  #   - the inviter is a Bot, carrying out invitations for a GitHub App.
  #
  # Returns a boolean.
  def show_inviter?
    return false if !inviter
    return false if inviter.is_a?(Bot)
    inviter != organization
  end

  # Public: Get the attached team invitation for the specified team.
  #
  # team - Team to get the invitation for.
  #
  # Returns a TeamInvitation, or nil if the specified team has no invitation.
  def team_invitation_for(team)
    if association(:team_invitations).loaded?
      team_invitations.detect { |team_inv| team_inv.team_id == team.id }
    else
      team_invitations.where(team_id: team.id).first
    end
  end

  # Public: The String representation of the OrganizationInvitation. If the
  # invitation is for a user it will return the user's safe profile name. If the
  # invitation is for an email invitation it will return the email.
  #
  # Returns String.
  def email_or_invitee_name
    if email?
      email
    else
      T.must(invitee).safe_profile_name
    end
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
      T.must(invitee).login
    end
  end

  # Public: indicate that the invitee has opted-out of receiving future
  # invitations from this organization
  #
  # Note: When the invitation is for a GitHub user *all* associated UserEmails
  # will be opted out.
  #
  # Returns an OrganizationInvitation::OptOut model
  def opt_out(actor:)
    T.must(organization).instrument(:opt_out_invitation, event_payload.merge(actor: actor))
    OrganizationInvitation::OptOut.opt_out(
      org: organization,
      email: email,
      invitee: invitee,
      invitation: self,
    )
  end

  def opted_out?
    OrganizationInvitation::OptOut.opted_out?(org: organization, email: email, invitee: invitee)
  end

  def email=(address)
    self.normalized_email = begin
        UserEmail.normalize(address)
      rescue ArgumentError
        nil # bad email address
      end

    write_attribute(:email, address)
  end

  # Public: Stores the raw token in-memory so it's available for the duration of
  # the request. Stores a hash of the token in the database to be used to lookup
  # invitations by token.
  #
  # Returns the set token.
  def token=(token_value)
    self.hashed_token = OrganizationInvitation.digest_token(token_value.to_s)
    @token = token_value
  end
  attr_reader :token

  # Public: Resets the token and saves the invitation. Since token is only stored
  # in-memory, this is needed to regenerate links for an invitation (e.g. to resend
  # and invitation email)
  #
  # Returns a Boolean indicating if the reset was successful.
  def reset_token
    return false unless email?

    generate_token && save
  end

  # Public: Checks if this invitation should be prevented from being created/updated/accepted
  #
  # N.B. This could be a validation, but it was very noisy and caused the incorrect messaging to be displayed.
  #
  # Returns Boolean
  def prevented_by_trade_controls_restrictions?
    organization&.has_full_trade_restrictions?
  end

  def instrument_retry_invite(actor:)
    GlobalInstrumenter.instrument "organization.retry_invitation", {
      actor: actor,
      email: email,
      invitation: self,
      organization: organization,
      user: invitee,
    }
  end

  # Public: Checks whether the invite is older than the set expiry period
  #
  # Returns a Boolean
  def invite_expired?
    return false unless self.can_expire?
    T.must(created_at).before? GitHub.invitation_expiry_period.days.ago
  end

  # Public: Org invitations created by external identity providers do not expire.
  # For example invitations generated during SCIM provisioning.
  #
  # Returns a Boolean
  def can_expire?
    !self.created_by_external_identity_provider?
  end

  def expire
    update(failed_reason: :expired)
    instrument_invite_expired
  end

  # Public: is the invitation created from an IdP?
  # For example during SCIM provisioning.
  #
  # Returns a Boolean
  def created_by_external_identity_provider?
    external_identity_id?
  end

  def bundled_license_assignments
    return @bundled_license_assignments if defined? @bundled_license_assignments
    assignment_email = email.present? ? email : invitee&.email
    organization = T.must(self.organization)
    return [] unless organization.business&.volume_licensing_enabled? && assignment_email.present?
    @bundled_license_assignments = organization.business&.bundled_license_assignments&.where(email: assignment_email)
  end

  def to_pending_invitation(source: nil)
    Business::PendingInvitation.from_organization_invitation(self, source: source)
  end

  def acceptor_needs_to_verify_email?(acceptor:, instrument: false)
    return unless email?

    instrument_email_verification(acceptor: acceptor) if instrument
    T.must(organization).org_invite_email_verification_enabled? && !actor_has_verified_email?(actor: acceptor)
  end

  def actor_can_cancel_email_invite?(actor:)
    # When the org_invite_email_verification feature flag is removed,
    # this method and `acceptor_needs_to_verify_email?` above will be interchangeable so will want to remove this one
    return unless email?
    T.must(organization).org_invite_email_verification_enabled? && actor_has_verified_email?(actor: actor)
  end

  private

  def actor_has_verified_email?(actor:)
    return @actor_has_verified_email if defined? @actor_has_verified_email
    @actor_has_verified_email = actor.emails.verified.where(email: email).any?
  end

  # Internal: Search for an external identity that matches the email address of the invite
  # and link it
  def link_external_identity(user:)
    return unless T.must(organization).saml_sso_enabled?
    return unless email.present?

    return unless external_identity.present?
    external_identity = T.must(self.external_identity)

    return if external_identity.user.present?

    external_identity.user = user

    external_identity.save
  end

  # Internal: Record metrics when accepting the invitation.
  def record_accept_metrics(via_email:, &block)
    GitHub.dogstats.distribution \
      "organization_invitation.time",
      GitHub::Dogstats.duration(created_at),
      tags: ["action:seconds_between_invite_and_accept"]

    if email?
      GitHub.dogstats.increment("organization_invitation", tags: ["action:accept", "via:email", "email_verification_required:#{T.must(organization).org_invite_email_verification_enabled?}"])
    else
      if via_email
        if reinstate?
          GitHub.dogstats.increment("organization_invitation", tags: ["action:accept", "via:email", "reinstate:true"])
        else
          GitHub.dogstats.increment("organization_invitation", tags: ["action:accept", "via:email", "reinstate:false"])
        end
      else
        if reinstate?
          GitHub.dogstats.increment("organization_invitation", tags: ["action:accept", "via:web", "reinstate:true"])
        else
          GitHub.dogstats.increment("organization_invitation", tags: ["action:accept", "via:web", "reinstate:false"])
        end
      end
    end

    GitHub.dogstats.distribution_time("organization_invitation.time", tags: ["action:accept"], &block)
  end

  def event_payload
    payload = {
      actor: inviter,
      invitation_id: self.id,
    }

    if email?
      payload[:email] = email
      payload[:invitee_email] = email
    else
      payload[:user] = invitee
      payload[:spammy] = invitee.try(:spammy)
    end

    payload
  end

  def instrument_invite_member
    T.must(organization).instrument(:invite_member, event_payload)

    GlobalInstrumenter.instrument "organization.invite_member", {
      actor: inviter,
      email: email,
      invitation: self,
      organization: organization,
      user: invitee,
    }
  end

  # This instrumentation is used by Copilot (and other interested subscribers) to know when an invite has been accepted.
  def instrument_accept_invite
    GlobalInstrumenter.instrument "org.member_invite_accepted", {
      actor: inviter,
      email: email,
      invitation: self,
      organization: organization,
      user: invitee,
      specified: true,
    }
  end

  def instrument_cancel_invite(actor:)
    T.must(organization).instrument(:cancel_invitation, event_payload.merge(actor: actor))

    GlobalInstrumenter.instrument "organization.cancel_invitation", {
      actor: actor,
      email: email,
      invitation: self,
      organization: organization,
      user: invitee,
    }
  end

  # This instrumentation is used by Copilot (and other interested subscribers) to know when an invite has been expired.
  def instrument_invite_expired
    GlobalInstrumenter.instrument "org.member_invite_expired", {
      actor: inviter,
      email: email,
      invitation: self,
      organization: organization,
      user: invitee,
      specified: true,
    }
  end

  def instrument_email_verification(acceptor:)
    GitHub.dogstats.increment("organization_invitation.verified_email", tags: [
      "email_verification_enabled:#{T.must(organization).org_invite_email_verification_enabled?}",
      "verified_email:#{actor_has_verified_email?(actor: acceptor)}",
    ])
  end

  def inviter_must_not_be_blocked
    if inviter && invitee
      errors.add(:invitee, "is blocking inviter") if T.must(inviter).blocked_by?(invitee)
    end
  end

  def email_must_be_exclusive
    if !invitee_id? && !email?
      errors.add(:base, "invitee or email must be present")
    elsif invitee_id? && email?
      errors.add(:email, "invitee has already been set")
    end
  end

  def invitee_must_not_be_opted_out
    return unless organization
    if opted_out?
      errors.add(:opt_out, "invitee has opted out of invitations from this organization")
    end
  end

  def email_must_not_be_prefixed
    if email? && T.must(email).start_with?("mailto:")
      errors.add(:email, "should not be prefixed")
    end
  end

  def org_must_not_be_spammy
    return unless organization && GitHub.spamminess_check_enabled?
    if T.must(organization).spammy?
      errors.add(:base, "User could not be added")
    end
  end

  # Private: Generates the token used to lookup email invitations.
  def generate_token
    self.token = SecureRandom.hex(20)
  end

  # Private: add a user to the organization. The user's org permissions are based on
  # the invitation's 'role' variable
  def add_user_to_organization(user)
    organization = T.must(self.organization)
    case role
    when "direct_member"
      organization.add_member(user, adder: inviter, invitation: self)
    when "admin"
      organization.add_admin(user, adder: inviter, invitation: self)
    when "billing_manager"
      organization.billing.add_manager(user, actor: inviter, invitation: self)
    when "reinstate"
      restorable = Restorable::OrganizationUser.restorable(organization, user)
      if restorable.restorable?
        organization.restore_membership(restorable, actor: inviter)
      else
        organization.add_member(user, adder: inviter, invitation: self)
      end
    end

    # Always ensure the restorable has been removed for potential fresh-start invitations
    if role != "reinstate"
      restorable = Restorable::OrganizationUser.restorable(organization, user)
      restorable.destroy if restorable.restorable?
    end
  end

  def snapshot_license_state
    return unless T.must(organization).delegate_billing_to_business?

    Licensing::SnapshotLicensesJob.perform_later(T.must(organization).business)
  end

  def update_business_license_usage
    T.must(organization).business&.update_license_usage
  end
end
