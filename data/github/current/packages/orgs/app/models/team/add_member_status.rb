# typed: true
# frozen_string_literal: true

# Public: A response is created when a user is added to a team.
class Team::AddMemberStatus
  MESSAGES = {
    blocked: "You are blocked from joining this organization. ",
    no_seat: "There are no available seats in this organization. ",
    no_2fa: "You do not satisfy the 2FA requirements of this organization. ",
    github_employee_no_sms_2fa: "You must have 2FA configured with an Authenticator app and not SMS/Text message in order to join the github organization as an employee. ",
    github_employee_no_passwordless: "You must have a password set in order to join the github organization as an employee. ",
    no_saml_sso: "You do not satisfy the SAML SSO requirements of this organization. ",
    dupe: "You are already a member. ",
    pending_cycle_no_seat: "There are no available seats in this organization during the pending cycle. ",
    no_permission: "Your inviter does not have permission to invite you. ",
    not_user: "You are not a valid user for this organization. ",
    trade_controls_restricted: "#{::TradeControls::Notices.notice_as_plaintext(:org_invite_restricted)} ",
    not_array: "The argument passed is not an array.",
    enterprise_team_managed: "This team is managed by an Enterprise Team. Instead, add the member directly to the Enterprise Team.",
    org_flagged_spammy: "Team members cannot be invited to this organization because it has been flagged.",
    rate_limit_exceeded: "In order to prevent abuse, we've limited the number of organization invitations you can send in a day. Try inviting new members tomorrow or contact support.",
  }

  BUSINESS_MESSAGES = {
    no_seat: "There are no available seats in this enterprise. ",
    pending_cycle_no_seat: "There are no available seats in this enterprise during the pending cycle. ",
  }

  # Internal: Successful statuses. FIX: The API needs duplicate member adds to
  # be successful, but I think we should take another look later.
  SUCCESSFUL = [:dupe, :success]

  # Public: A Symbol. :success, :blocked, :no_seat, :no_2fa, :no_saml_sso, :dupe, or :org.
  attr_reader :status

  def initialize(status)
    @status = status
    freeze
  end

  private :initialize

  # Public: Did an error occur while adding a member?
  def error?
    !success?
  end

  def should_failover?
    !success? && status != :not_user
  end

  # Public: Was a member successfully added?
  def success?
    SUCCESSFUL.include?(status)
  end

  # Public: Describe the error if any.
  def message
    MESSAGES[status]
  end

  def business_message
    BUSINESS_MESSAGES[status] || MESSAGES[status]
  end

  # Public: compare the status of two AddMemberStatus
  def ==(other)
    other.is_a?(Team::AddMemberStatus) && status == other.status
  end

  # Public: User isn't permitted to join a team.
  BLOCKED = new(:blocked)

  # Public: Team can't be added to due to org level trade controls restrictions
  TRADE_CONTROLS_RESTRICTED = new(:trade_controls_restricted)

  # Public: User isn't permitted to join because there isn't an available seat.
  NO_SEAT = new(:no_seat)

  # Public: User isn't permitted to join because there will not be an available seat after the orgs pending downgrade.
  PENDING_CYCLE_NO_SEAT = new(:pending_cycle_no_seat)

  # Public: User isn't permitted to join because they don't satisfy the 2FA requirement.
  NO_2FA = new(:no_2fa)

  # Public: User isn't permitted to join because they don't satisfy the 2FA requirement of the github/employees team (may not have any SMS 2FA registrations)
  GITHUB_EMPLOYEE_NO_SMS_2FA = new(:github_employee_no_sms_2fa)

  # Public: User isn't permitted to join because they do not have a password set (github/employees team)
  GITHUB_EMPLOYEE_NO_PASSWORDLESS = new(:github_employee_no_passwordless)

  # Public: User isn't permitted to join because they don't satisfy the SAML SSO requirement.
  NO_SAML_SSO = new(:no_saml_sso)

  # Public: User is already a member of a team.
  DUPE = new(:dupe)

  # Public: User is not a human user, and can't join any team.
  NOT_USER = new(:not_user)

  # Public: It's all good.
  SUCCESS = new(:success)

  # Public: Inviter doesn't have permission to invite
  NO_PERMISSION = new(:no_permission)

  # Public: Not an array
  NOT_AN_ARRAY = new(:not_array)

  # Public: This team is managed by an Enterprise Team
  ENTERPRISE_TEAM_MANAGED = new(:enterprise_team_managed)

  # Public: The org is flagged spammy
  ORG_FLAGGED_SPAMMY = new(:org_flagged_spammy)

  # Public: User isn't permitted to join because the organization has exceeded the invitation rate limit.
  RATE_LIMIT_EXCEEDED = new(:rate_limit_exceeded)

  # Public: User is suspended and cannot be added to a team
  SUSPENDED = new(:suspended)
end
