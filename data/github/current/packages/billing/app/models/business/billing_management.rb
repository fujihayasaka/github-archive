# typed: true
# frozen_string_literal: true

class Business::BillingManagement
  include Ability::Subject
  include Ability::Membership

  def initialize(business)
    @business = business
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

    grant user, :write

    payload = { user: user }
    if staff_action
      payload.update(GitHub.guarded_audit_log_staff_actor_entry(actor))
    else
      payload.update(actor: actor)
    end
    @business.instrument :add_billing_manager, payload

    @business.add_user_accounts([user.id]) unless GitHub.single_business_environment?
    GitHub.dogstats.increment("billing.managers.count", tags: ["action:add"])

    @business.send_admin_added_email_notification(
      role: Business::BILLING_MANAGER_ROLE,
      admin: user
    ) if send_notification
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

    remove(user)

    @business.instrument :remove_billing_manager,
      user: user,
      actor: actor,
      reason: reason
    GlobalInstrumenter.instrument("enterprise_account.remove_admin", {
      enterprise: @business,
      actor: actor,
      user: user,
      role: :billing_manager,
      reason: reason,
      new_role: new_role,
    })
    GitHub.dogstats.increment("billing.managers.count", tags: ["action:remove"])

    @business.send_admin_removed_email_notification(
      role: Business::BILLING_MANAGER_ROLE,
      admin: user,
      reason: reason&.to_s
    ) if send_notification
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

  # Internal: Remove the user from their billing management role
  #
  # user - The User to remove
  def remove(user)
    @business.cancel_all_invitations_involving(user)
    revoke user
    # do not remove business user account if the user is enterprise managed
    @business.cleanup_removed_user(user) unless user.is_enterprise_managed?
  end
end
