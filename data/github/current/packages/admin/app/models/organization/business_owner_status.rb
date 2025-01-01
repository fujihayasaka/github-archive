# typed: true
# frozen_string_literal: true

# Public: A response is created when a business owner is added to an org.
class Organization::BusinessOwnerStatus
  MESSAGES = {
    no_seat: "There are no available seats in this organization. ",
    no_2fa: "You do not satisfy the 2FA requirements of this organization. ",
    no_owners: "You can't remove the last owner of this organization. ",
    no_permission: "Your inviter does not have permission to invite you. ",
    not_successful: "Performing this action was not successful. ",
    invalid_user_state: "User cannot be added to this organization. ",
    saml_enforced: "SAML is enforced on this organization. You cannot add users directly. ",
    emu_member_in_external_group: "Unable to remove enterprise managed user from the organization who belongs to an external group. ",
    member_in_synced_enterprise_team: "Unable to remove user from the organization who belongs to a synced enterprise team. ",
    membership_granted_through_business_team: "Unable to remove user from the organization who was granted membership through an enterprise team. ",
  }

  # Public: A Symbol. :success, :no_seat, :no_2fa, :not_successful
  attr_reader :status

  def initialize(status)
    @status = status
    freeze
  end

  private :initialize

  # List of successful statuses
  SUCCESSFUL = [:success_owner, :success_member, :success_removed, :no_change]

  # Public: Did an error occur while adding this owner?
  def error?
    !success?
  end

  # Public: Was an owner successfully added?
  def success?
    SUCCESSFUL.include?(status)
  end

  # Public: Describe the error if any.
  def message
    MESSAGES[status]
  end

  # Public: User isn't permitted to join because there isn't an available seat.
  NO_SEAT = new(:no_seat)

  # Public: User isn't permitted to join because they don't satisfy the 2FA requirement.
  NO_2FA = new(:no_2fa)

  # Public: Successfully become an org owner
  SUCCESS_OWNER = new(:success_owner)

  # Public: Successfully become an org member
  SUCCESS_MEMBER = new(:success_member)

  # Public: Successfully removed from the org
  SUCCESS_REMOVED = new(:success_removed)

  # Public: Inviter doesn't have permission to invite
  NO_PERMISSION = new(:no_permission)

  # Public: Owner cannot be removed because no other owners on Org
  NO_OWNERS = new(:no_owners)

  # Public: If the user has derived membership, then the user cannot be removed
  EMU_MEMBER_IN_EXTERNAL_GROUP = new(:emu_member_in_external_group)

  # Public: If the user is a member of a synced enterprise team, then the user cannot be removed
  MEMBER_IN_SYNCED_ENTERPRISE_TEAM = new(:member_in_synced_enterprise_team)

  # Public: If the user was granted member through a business team, then the user cannot be removed
  MEMBERSHIP_GRANTED_THROUGH_BUSINESS_TEAM = new(:membership_granted_through_business_team)

  # Public: Was not successful for a reason not given here
  NOT_SUCCESSFUL = new(:not_successful)

  # Public: No change was made.
  NO_CHANGE = new(:no_change)

  # Public: User is suspended or deceased
  INVALID_USER_STATE = new(:invalid_user_state)

  # Public: SAML is enforced on the org and user is not a member
  SAML_ENFORCED = new(:saml_enforced)
end
