# typed: true
# frozen_string_literal: true

class Business::BillingManagement
  include Ability::Subject
  include Ability::Membership

  def initialize(business)
    @business = business
  end

  # Public: Grant the billing manager Ability to the given User on the Business.
  #
  # user - The User to whom the Ability should be granted.
  def grant_manager_ability(user)
    grant(user, :write)
  end

  # Public: Revoke the billing manager Ability for the given user on the Business.
  #
  # user - The User for whom the Ability should be revoked.
  def revoke_ability(user)
    revoke(user)
  end

  # Add a billing manager.
  #
  # user        - The User to add as a billing manager
  # actor       - The User adding the billing manager
  # send_notification - Whether or not the user should be sent a notification
  #                     about being added to the business (default: false).
  # staff_action - true if the original add or invite originated from stafftools so hide staff user information.
  #   There is a catchall if actions come directly from a stafftools endpoint, but if data is persisted or scheduled
  #   for later work we might accidentally expose support logins.
  #
  # Returns nothing.
  def add_manager(user, actor:, send_notification: false, staff_action: false)
    validate(user, Business::BILLING_MANAGER_ROLE)

    BusinessOrchestration.add_billing_managers(
      business: @business,
      user_ids: [user.id],
      actor: actor,
      send_email_notification: send_notification,
      staff_action: staff_action
    ).execute(synchronous: true)
  end

  # Remove a billing manager.
  #
  # user    - A User, who's being removed as a billing manager of the business
  # actor   - The User revoking the privilege.
  # reason  - (Optional) A String stating why the privilege was revoked.
  # send_notification - Whether or not the user should be sent a notification
  #                     about being removed from the business. (default: true)
  #
  # Returns nothing.
  def remove_manager(user, actor:, reason: nil, send_notification: true, new_role: nil)
    return unless manager?(user)

    BusinessOrchestration.remove_billing_managers(
      business: @business,
      user_ids: [user.id],
      actor: actor,
      reason: reason,
      send_email_notification: send_notification,
      new_role: new_role
    ).execute(synchronous: true)
  end

  def ability_id
    @business.id
  end

  # Returns true if the given user is a billing manager of this business.
  def manager?(user)
    permit?(user, :write)
  end

  # Returns a list of billing managers for this business
  def managers
    members(action: :write)
  end

  # Returns a list of billing manager ids for this business
  def manager_ids
    member_ids(action: :write)
  end

  # Internal: Remove all billing managers, used when destroying a business
  def remove_all_managers
    members.each do |member|
      if manager?(member)
        remove_manager(member, actor: nil, send_notification: false)
      end
    end
  end

  # Internal: See Ability::Subject#grant?
  def grant?(actor, action)
    @business.grant?(actor, action)
  end

  def target_for_conditional_access
    @business
  end

  private

  # Internal: Verify that the user is eligible for a billing management role
  #
  # user - The User to validate
  # role - The role to validate
  #
  # Returns nothing.
  def validate(user, role)
    unless @business.valid_administrator_state?(user)
      raise Business::InvalidAdminStateError, "User cannot be added as a #{role}"
    end

    if !@business.external_identity_session_owner.saml_sso_requirement_met_by?(user)
      raise Business::UserHasNoExternalIdentityError, "User must have a linked external identity provisioned by the identity provider"
    end
  end
end
