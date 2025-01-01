# typed: true
# frozen_string_literal: true

class BusinessMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/business"

  helper :application
  helper :avatar
  helper :email_link_tracking

  layout "layouts/primer_layout"

  DOCS_LINKS = {
    account:      "https://docs.github.com/enterprise-cloud@latest/admin/overview/about-enterprise-accounts",
    entitlements: "https://docs.github.com/enterprise-cloud@latest/admin/user-management/managing-users-in-your-enterprise/managing-support-entitlements-for-your-enterprise",
    policies:     "https://docs.github.com/enterprise-cloud@latest/admin/policies",
    license:      "https://docs.github.com/enterprise-server@latest/billing/managing-your-license-for-github-enterprise/downloading-your-license-for-github-enterprise",
    ghes_sla:     "https://docs.github.com/enterprise-server/admin/enterprise-support/overview/about-github-premium-support-for-github-enterprise",
    ghec_sla:     "https://docs.github.com/enterprise-cloud@latest/github/working-with-github-support/about-github-premium-support-for-github-enterprise-cloud",
  }

  # Public: Notify enterprise owners when the enterprise is soft-deleted.
  #
  # actor - User who performed the deletion.
  # business_id - Integer representing the ID of the Business that was deleted.
  #
  # Returns Mail.
  def business_deleted(actor, business_id)
    @actor = actor
    @business = Business.including_deleted.find_by(id: business_id)
    return unless @business.present?

    subject = "[GitHub] The #{@business.name} enterprise has been deleted"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@business),
      subject: subject
  end

  def failed_two_factor_enforcement(actor, business)
    @actor = actor
    @business = business

    subject = "[GitHub] Failed to enable and enforce two-factor requirement for #{business.name} enterprise"

    premail(
      from: github_noreply,
      to: user_email(actor, GitHub.newsies.email(actor).value),
      subject: subject,
    )
  end

  sig do
    params(
      actor: User,
      business: Business,
      role_and_preposition: String
    ).returns(T.any(String, Mail::Message))
  end
  def two_factor_enforcement_member_notification(actor, business, role_and_preposition)
    @actor = actor
    @business = business
    @role_and_preposition = role_and_preposition

    subject = "[GitHub] #{@business.name} now requires two-factor authentication"

    premail(
      from: github_noreply,
      to: user_email(actor, GitHub.newsies.email(actor).value),
      subject: subject,
    )
  end

  sig do
    params(
      actor: User,
      business: Business,
      role_and_preposition: String
    ).returns(T.any(String, Mail::Message))
  end
  def insecure_two_factor_method_enforcement_member_notification(actor, business, role_and_preposition)
    @actor = actor
    @business = business
    @role_and_preposition = role_and_preposition

    subject = "[GitHub] #{@business.name} is only allowing secure two-factor authentication"

    premail(
      from: github_noreply,
      to: user_email(actor, GitHub.newsies.email(actor).value),
      subject: subject
    )
  end

  # Public: Notify someone that they have been invited to be a business owner.
  #
  # This method works for either an invitation to just an email address, or an
  # invitation to an existing invitee.
  #
  # invitation - The BusinessAdministratorInvitation
  # invitation_token - If it's an invitation to an email address, the String
  #   token for the invitation. Defaults to nil.
  # reinvited_count - Integer representing the number of times an admin has been
  #   re-invited. Defaults to 0.
  #
  # Returns Mail.
  def invited_as_business_owner(invitation, invitation_token = nil, reinvited_count = 0)
    @invitation = invitation
    @invitation_token = invitation_token
    @user = invitation.invitee
    @email = invitation.email
    @inviter = invitation.inviter
    @business = invitation.business
    @show_inviter = invitation.show_inviter?
    @reinvited_count = reinvited_count.presence || 0

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support
    # address if not.
    reply_to = user_email(invitation.inviter, allow_private: false) if @show_inviter
    reply_to ||= github

    subject = if @show_inviter
      "[GitHub] @#{@inviter.display_login} has invited you to become an owner of the #{@business.name} enterprise"
    else
      "[GitHub] You’re invited to become an owner of the #{@business.name} enterprise"
    end

    premail(
      from: github,
      reply_to: reply_to,
      to: @user.present? ? user_email(@user) : @email,
      subject: subject,
    )
  end

  # Public: Notify user that their invitation to become a business owner has
  # been cancelled.
  #
  # invitation - The BusinessAdministratorInvitation
  #
  def business_admin_invitation_cancelled(invitation)
    @invitation = invitation
    @email = @invitation.email? ? @invitation.email : user_email(@invitation.invitee)
    @business = @invitation.business

    premail(
      from: github,
      to: @email,
      subject: "[GitHub] Your invitation to become an owner of #{@business.name} has been canceled",
    )
  end

  # Public: Notify a user that they have been added as an enterprise account
  # admin (owner or billing manager).
  #
  # Note: This is currently only used when GitHub staff directly add admins to
  # an enterprise account, and the regular invitation workflow is bypassed.
  #
  # business   - The Business.
  # admin_role - A Symbol representing the role of the admin (:owner or :billing_manager).
  # user       - The User that was added.
  #
  def added_as_business_admin(business, admin_role, user)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @business = business
    @user = user
    @role_for_email = role_for_business_email(admin_role)

    subject = "[GitHub] You’ve been added as #{@role_for_email} of the #{@business.name} enterprise"

    premail(
      from: github,
      to: user_email(@user),
      subject: subject,
    )
  end

  # Public: Notify a user that they have been removed as an enterprise account
  # admin (owner or billing manager).
  #
  # Called when they are removed via the UI, a GraphQL call, or because they had
  # become non-compliant with 2fa policy
  #
  # business   - The Business.
  # admin_role - A Symbol representing the role of the admin (:owner or :billing_manager).
  # user       - The User that was removed.
  # reason     - (optional) the reason the user was removed
  #
  def removed_as_business_admin(business, admin_role, user, reason = nil)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @business = business
    @user = user
    @role_for_email = role_for_business_email(admin_role)
    @reason = reason&.to_sym

    subject = "[GitHub] You’ve been removed as #{@role_for_email} of the #{@business.name} enterprise"

    premail(
      from: github,
      to: user_email(@user),
      subject: subject,
    )
  end

  # Public: Notify a user that they have been removed from an enterprise account.
  #
  # Called when they are removed via a GraphQL call (or in the future via the UI)
  #
  # business - The Business.
  # user - The User that was removed.
  # user_roles - The roles that the user lost as a result of being removed. Could be any of :owner,
  #   :billing_manager, :member, and/or :outside_collaborator
  # organizations - (optional) the Organizations the user was removed from
  #
  def removed_as_business_member(business, user, user_roles, organizations)
    @business = business
    @user = user
    @organizations = organizations
    @org_count = @organizations.length
    @lookup_org_owner_help_doc_url = OrganizationMailer::LOOKUP_ORG_OWNER_HELP_DOC_URL
    @roles = Array(user_roles).map { |role| role_for_business_email(role) }

    # users might be admins and not belong to any organizations
    subject_parts = ["[GitHub] You’ve been removed from"]
    subject_parts << "#{@org_count} #{"organization".pluralize(@org_count)} in" if @org_count > 0
    subject_parts << "the #{@business.name} enterprise"

    premail(
      from: github,
      to: user_email(@user),
      subject: subject_parts.join(" "),
    )
  end

  def remove_user_from_business_failed(business, actor, user, failure, organizations = nil)
    @business = business
    @user = user
    @actor = actor
    @organizations = organizations
    @failure = failure.to_s

    subject = ["[GitHub] We could not remove @#{@user.display_login} from the #{@business.name} enterprise"]

    premail(
      from: github,
      to: user_email(@actor),
      subject: subject,
    )
  end

  # Public: Notify an enterprise admin when their role within the enterprise has
  # changed (owner <=> billing manager)
  #
  # business        - The Business
  # new_admin_role  - the admin's new role with the enterprise (:owner or :billing_manager)
  # user            - the admin whose role has changed
  #
  def admin_role_changed(business, new_admin_role, user)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @business = business
    @user = user
    @role_for_email = role_for_business_email(new_admin_role)

    subject = "[GitHub] Your role with the #{@business.name} enterprise has changed, and you are now #{@role_for_email}."

    premail(
        from: github,
        to: user_email(@user),
        subject: subject,
    )
  end

  def invited_as_business_billing_manager(invitation, invitation_token)
    @invitation = invitation
    @user = invitation.invitee
    @email = invitation.email
    @inviter = invitation.inviter
    @business = invitation.business
    @show_inviter = invitation.show_inviter?
    @url = if invitation.email?
      enterprise_billing_manager_invitation_url(@business, invitation_token: invitation_token)
    else
      enterprise_billing_manager_invitation_url(@business)
    end

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support address if
    # not.
    if @show_inviter
      reply_to = user_email(@inviter, allow_private: false)
    end
    reply_to ||= github

    subject = if @show_inviter
      "[GitHub] @#{@inviter.display_login} has invited you to be a billing manager for the #{@business.name} enterprise"
    else
      "[GitHub] You're invited to be a billing manager for the #{@business.name} enterprise"
    end

    premail(
      from: github,
      to: invitation.email? ? invitation.email : user_email(@user),
      subject: subject,
      reply_to: reply_to,
    )
  end

  def invited_as_business_unaffiliated_member(invitation, invitation_token)
    @invitation = invitation
    @user = invitation.invitee
    @email = invitation.email
    @inviter = invitation.inviter
    @business = invitation.business
    @show_inviter = invitation.show_inviter?
    @url = if invitation.email?
      enterprise_member_invitation_url(@business, invitation_token: invitation_token)
    else
      enterprise_member_invitation_url(@business)
    end

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support address if
    # not.
    if @show_inviter
      reply_to = user_email(@inviter, allow_private: false)
    end
    reply_to ||= github

    subject = if @show_inviter
      "[GitHub] @#{@inviter.display_login} has invited you to join the #{@business.name} enterprise"
    else
      "[GitHub] You're invited to join the #{@business.name} enterprise"
    end

    premail(
      from: github,
      to: invitation.email? ? invitation.email : user_email(@user),
      subject: subject,
      reply_to: reply_to,
    )
  end

  # Public: Notify organization that they have been invited to be a part of a business.
  #
  # invitation - The BusinessOrganizationInvitation
  #
  def invited_organization(invitation)
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support
    # address if not.
    reply_to = user_email(@inviter, allow_private: false) if invitation.show_inviter?
    reply_to ||= github

    subject = if invitation.show_inviter?
      "[GitHub] @#{@inviter.display_login} has invited #{@organization.name} to join #{@business.name} enterprise"
    else
      "[GitHub] #{@organization.name} has been invited to to join #{@business.name} enterprise"
    end

    premail(
      from: github,
      reply_to: reply_to,
      bcc: organization_emails(@organization),
      subject: subject,
    )
  end

  # Public: Notify all enterprise owners that an invited organization has
  # accepted their invitation and is waiting on confirmation to
  # finalize the transfer.
  #
  # invitation - The BusinessOrganizationInvitation
  #
  def invited_organization_accepted(invitation, actor)
    @actor = actor
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business

    reply_to = @organization.profile_email || user_email(@organization.admins.first, allow_private: false)
    reply_to ||= github

    subject = "[GitHub] @#{@actor.display_login} has accepted the invitation for #{@organization.name} to join the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  # Public: Notify all enterprise owners that an invited organization has
  # rejected their invitation.
  #
  # invitation - The BusinessOrganizationInvitation
  #
  def invited_organization_rejected(invitation, actor)
    @actor = actor
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business

    reply_to = @organization.profile_email || user_email(@organization.admins.first, allow_private: false)
    reply_to ||= github

    subject = "[GitHub] @#{@actor.display_login} has rejected the invitation for #{@organization.name} to join the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  # Public: Notify enterprise owners and org admins that the invitation
  # has been finalized and the organization is now part of the
  # enterprise account.
  #
  # invitation - The BusinessOrganizationInvitation
  #
  def invited_organization_finalized(invitation, actor)
    @actor = actor
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support
    # address if not.
    reply_to = user_email(@inviter, allow_private: false) if invitation.show_inviter?
    reply_to ||= github

    subject = "[GitHub] #{@organization.name} has joined the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business) + organization_emails(@organization),
      subject: subject,
    )
  end

  # Public: Notify enterprise owners and org admins that an
  # organization has been been added by github staff to their
  # enterprise account.
  #
  # organization - The Organization that was added
  # business - The Business the organization was added to
  #
  def invited_organization_finalized_stafftools(organization, business)
    @organization = organization
    @business = business

    reply_to = github

    subject = "[GitHub] #{@organization.name} has joined the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business) + organization_emails(@organization),
      subject: subject,
    )
  end

  # Public: Send a reminder email when the invitation for the org to join the
  # enterprise has not been accepted.
  #
  # invitation - The BusinessOrganizationInvitation.
  #
  # Returns Mail.
  def organization_invitation_pending_acceptance_reminder(invitation)
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business
    @until_expiry_in_words = invitation.until_expiry_in_words

    reply_to = user_email(@inviter, allow_private: false) if invitation.show_inviter?
    reply_to ||= github

    subject = "[GitHub] Reminder that #{@organization.name} has been invited to join the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: organization_emails(@organization),
      subject: subject,
    )
  end

  # Public: Send a reminder email to enterprise owners when the invitation for
  # the org to join the enterprise has not been confirmed.
  #
  # invitation - The BusinessOrganizationInvitation
  #
  # Returns Mail.
  def organization_invitation_pending_confirmation_reminder(invitation)
    @invitation = invitation
    @organization = invitation.invitee
    @inviter = invitation.inviter
    @business = invitation.business
    @until_expiry_in_words = invitation.until_expiry_in_words

    reply_to = @organization.profile_email || user_email(@organization.admins.first, allow_private: false)
    reply_to ||= github

    subject = "[GitHub] Reminder to confirm the invitation for #{@organization.name} to join the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  # Public: Send an email when an organization is successfully transferred
  # from one enterprise to another.
  #
  # transfer - The BusinessOrganizationTransfer
  #
  # Returns Mail.
  def organization_transfer_completed(transfer)
    @transfer = transfer

    subject = "[GitHub] #{@transfer.organization} was transferred from \
      #{@transfer.from_business.name} to #{@transfer.to_business.name}".squish

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@transfer.from_business) +
        business_emails(@transfer.to_business) +
        organization_emails(@transfer.organization),
      subject: subject
  end

  # Public: Send an email when an organization transfer
  # from one enterprise to another fails unexpectedly.
  #
  # transfer - The BusinessOrganizationTransfer
  #
  # Returns Mail.
  def organization_transfer_failed(transfer)
    @transfer = transfer

    subject = "[GitHub] Transferring #{@transfer.organization} failed"

    premail \
      from: github,
      reply_to: github,
      bcc: business_emails(@transfer.from_business),
      subject: subject
  end

  # Public: Send an email when an organization is removed from an enterprise.
  #
  # business - The Business
  # organization - The Organization
  # plan - The new plan for the Organization
  #
  # Returns Mail.
  def organization_removed_from_business(business, organization, plan = nil)
    @business = business
    @organization = organization
    return if @business.blank? || @organization.blank?
    return if @business.deleted?

    @removed_org_add_payment_info_or_contact_sales = removed_org_add_payment_info_or_contact_sales?(
      business,
      organization
    )
    @plan = plan

    subject = "[GitHub] #{@organization.name} has been removed from the #{@business.name} enterprise"

    premail(
      from: github,
      reply_to: github,
      bcc: business_emails(@business) + organization_emails(@organization),
      subject: subject,
    )
  end

  # Public: Send an email when an Organization is upgraded to be part of a new
  # enterprise account.
  #
  # business - Business representing the newly created enterprise account
  # organization - Organization that is the initial member org in the enterprise
  # actor - User that created the new enterprise account
  # settings_transferred - Array of Hash of settings transferred from org to enterprise.
  #
  # Returns Mail.
  def business_created_from_organization(business, organization, actor, settings_transferred = [])
    @business = business
    @organization = organization
    @actor = actor
    @settings_transferred = settings_transferred

    subject = "[GitHub] #{@business.name} enterprise created for the #{@organization.name} organization"

    premail(
      from: github,
      reply_to: github,
      bcc: business_emails(@business, include_billing_managers: true),
      subject: subject,
    )
  end

  # Public: Send a welcome email when an enterprise trial account is created.
  #
  # actor - User that created the enterprise trial account
  # business - Business representing the created enterprise trial account
  #
  # Returns Mail.
  def welcome_enterprise_trial_account(actor, business)
    @actor = actor
    @business = business

    subject = "[GitHub] Welcome to your trial of GitHub Enterprise"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email 7 days before the trial period of an enterprise trial account is about to end.
  #
  # actor - User that created the enterprise trial account
  # business - Business representing the enterprise trial account
  #
  # Returns Mail.
  def trial_period_ending_for_enterprise_trial_account(actor, business)
    return if !business.trial? || business.trial_expired?

    # Ensure we don't send this email for enterprise trial account whose trial period was extended
    # and ending in more than 7 days, or whose trial ending in less than 6 days.
    if business.trial_expires_at > 7.days.from_now
      delivery_date = (business.trial_expires_at - 7.days).to_datetime
      BusinessMailer.trial_period_ending_for_enterprise_trial_account(actor, business).deliver_later(
        wait_until: delivery_date
      )
      return
    elsif business.trial_expires_at < 6.days.from_now
      return
    end

    @actor = actor
    @business = business

    subject = "[GitHub] Your GitHub Enterprise trial ends in seven days"

    @footer_links = [
      { url: "#{GitHub.support_url}/features/billing_and_payments", text: "Help with billing" },
      { url: "https://github.com/enterprise/contact?ref_page=/pricing&ref_cta=Contact%20Sales&ref_loc=cards", text: "Contact us" }
    ]

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email after trial period of an enterprise trial account has ended.
  #
  # actor - User that created the enterprise trial account
  # business - Business representing the enterprise trial account
  #
  # Returns Mail.
  def trial_period_ended_for_enterprise_trial_account(actor, business)
    return if !business.trial? || !business.trial_expired?

    @actor = actor
    @business = business
    @upgrade_url = if business.metered_plan?
      settings_billing_activations_enterprise_url(business)
    else
      billing_upgrade_enterprise_url(business)
    end
    @deletion_scheduled = @business.eligible_for_expired_trial_deletion? && \
                          @business.trial_deleted_at.present?

    subject = "[GitHub] Your GitHub Enterprise trial has ended"

    @footer_links = [
      { url: "#{GitHub.support_url}/features/billing_and_payments", text: "Help with billing" },
      { url: "https://github.com/enterprise/contact?ref_page=/pricing&ref_cta=Contact%20Sales&ref_loc=cards", text: "Contact us" }
    ]

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when an enterprise trial is cancelled.
  #
  # actor - User that created the enterprise trial account
  # business - Business representing the enterprise trial account
  # trial_expired - Boolean indicating whether the trial for the enterprise account was expired
  # prior to cancellation.
  #
  # Returns Mail.
  def cancel_trial_for_enterprise_trial_account(actor, business, trial_expired)
    return unless business.trial_cancelled?

    @actor = actor
    @business = business
    @cancelled_flavor = trial_expired ? "deleted" : "cancelled"

    subject = "[GitHub] Your GitHub Enterprise trial has been #{@cancelled_flavor}"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when an org upgrade payment fails.
  #
  # actor - User that is an owner of the enterprise account
  # business - Business representing the upgraded enterprise account
  #
  # Returns Mail.
  def purchased_org_upgrade_payment_failure(actor, business)
    @actor = actor
    @business = business

    subject = "[GitHub] Your purchase of GitHub Enterprise was unsuccessful"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when a payment for a business
  # created from coupon redemption fails.
  #
  # actor - User that is an owner of the enterprise account
  # business - Business representing the couponed enterprise account
  # coupon - Coupon that was originally redeemed for the business
  #
  # Returns Mail.
  def creation_from_coupon_purchase_failure(actor, business, coupon: nil)
    @actor = actor
    @business = business
    @coupon = coupon

    subject = "[GitHub] Your purchase of GitHub Enterprise was unsuccessful"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when a business
  # is succesfully created from coupon redemption.
  #
  # actor - User that created the enterprise account by redeeming a coupon
  # business - Business representing the couponed enterprise account
  # Note: if an org has been attached to this business, all org admins will become business owners.
  # However, admin transfer is done in a job so when email is queued, this may not have happened yet.
  # Emailing org admins ensures email is sent to all (future) admins of the business
  #
  # Returns Mail.
  def creation_from_coupon_success(actor, business)
    @actor = actor
    @business = business
    @organization = business.organizations.first

    subject = "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!"

    premail(
      from: github,
      reply_to: github,
      bcc: @organization.present? ? admin_emails(@organization) : business_emails(@business, include_billing_managers: true),
      subject: subject,
    )
  end

  # Public: Notify organization owners that the upgrade has been initiated
  # but still needs to be paid for.
  #
  # actor - owner of the enterprise account
  # organization - Organization that was being upgraded.
  #
  def organization_upgrade_pending(actor, business)
    @actor = actor
    @business = business
    return unless @org = @business.upgrade_initiated_from_organization
    return unless @business.organization_upgrade_initiated?

    if EnterpriseAccounts::KV.store.exists("organization_upgrade_purchase_initiated/#{@business.id}").value!
      ActiveRecord::Base.connected_to(role: :writing) do
        EnterpriseAccounts::KV.store.del("organization_upgrade_purchase_initiated/#{@business.id}")
      end

      return
    end

    subject = "[GitHub] Your organization upgrade is still pending"

    premail(
      from: github,
      reply_to: github,
      to: user_email(@actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when an org cannot be upgraded to an enterprise account due to insufficient seats.
  #
  # actor - User that is attempting to upgrade the organization to an enterprise account
  # business - Business that is being upgraded from an organization
  #
  # Returns Mail.
  def attach_organization_to_enterprise_failure(actor, business)
    @actor = actor
    @business = business
    @organization = business.upgrade_initiated_from_organization
    @additional_seats_needed = @business.additional_licenses_required_for_organization(@organization)

    subject = "[GitHub] Your organization upgrade to GitHub Enterprise is incomplete"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  # Public: Send a notification email when an enterprise trial upgrade fails.
  #
  # actor - User that is an owner of the enterprise trial account
  # business - Business representing the enterprise trial account
  #
  # Returns Mail.
  def unsuccessful_enterprise_trial_upgrade(actor, business)
    @actor = actor
    @business = business

    subject = "[GitHub] Your purchase of GitHub Enterprise was unsuccessful"

    premail(
      from: github,
      reply_to: github,
      to: user_email(actor),
      subject: subject,
    )
  end

  def notify_expired_trial_admins(business, user, trial_deleted_at)
    return unless business.present?
    return unless business.eligible_for_expired_trial_deletion?

    @business = business
    @trial_deleted_at = trial_deleted_at.strftime("%B %-d")
    @days_to_deletion = (trial_deleted_at.to_date - Time.zone.now.to_date).to_i
    @trial_billing_url = settings_billing_enterprise_url(@business)
    @restorable_period = Business::RESTORABLE_PERIOD.in_days.to_i
    @user = user

    subject = "[GitHub] Your GitHub Enterprise trial will be deleted in #{@days_to_deletion} #{"day".pluralize(@days_to_deletion)}"

    premail(
      from: github,
      reply_to: github,
      to: user_email(user),
      subject: subject,
    )
  end

  def notify_expired_enterprise_trial_deleted(business, user)
    return unless business.present?

    @business = business
    @restorable_period = Business::RESTORABLE_PERIOD.in_days.to_i
    @user = user

    subject = "[GitHub] Your GitHub Enterprise trial has been deleted"

    premail(
      from: github,
      reply_to: github,
      to: user_email(user),
      subject: subject,
    )
  end

  # Public - Notify a user that they've been removed from the Organizations in the Business
  # due to 2FA non-compliance
  #
  # user - the business member we're notifying
  # business - the Business that's enabling 2fa
  # organizations - list of oranizations in the Business that the user belongs to
  def removed_member_from_organizations(user, business, organizations)
    return if organizations.empty?

    @user = user
    @business = business
    @organizations = organizations
    @orgs_count = @organizations.length
    @lookup_org_owner_help_doc_url = OrganizationMailer::LOOKUP_ORG_OWNER_HELP_DOC_URL

    subject = "[GitHub] You've been removed from #{@orgs_count} #{"organization".pluralize(@orgs_count)} in the #{@business.name} enterprise"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
      categories: "org,org-remove-member",
    )
  end

  # Public - Notify a user that their outside collaborator status has been removed from
  # repositories that belong to this Business due to 2FA non-compliance
  #
  # user - the outside collaborator we're notifying
  # business - the Business that's enabling 2fa
  # repository_names - array of repository names that the user is losing access to
  #                    (:name_with_owner)
  def removed_outside_collaborator_from_organizations(user, business, repository_names)
    return if repository_names.empty?

    @user = user
    @business = business
    @repo_count = repository_names.length
    @repository_names = repository_names
    @lookup_org_owner_help_doc_url = OrganizationMailer::LOOKUP_ORG_OWNER_HELP_DOC_URL

    subject = "[GitHub] You've been removed from #{@repo_count} #{"repository".pluralize(@repo_count)} in the #{@business.name} enterprise"

    premail(
        from: github_noreply,
        to: user_email(@user),
        subject: subject,
        categories: "org,org-remove-outside-collaborator",
    )
  end

  # Public - Notify a user that an enterprise has restricted email notifications for all of
  # its member organizations and tell them which organizations they will no longer receive
  # notifications from (unless they add a verified email from a verified or approved domain)
  #
  # user - user to notify
  # business - enterprise that has enabled notification restrictions
  # organizations - organizations that the user is going to stop getting notifications from
  def notification_restrictions_enabled(user, business, organizations)
    @user = user
    @business = business
    @enterprise_domains = @business.verifiable_domains.verified_or_approved.map(&:domain)
    grouped_domains = VerifiableDomain.includes(:owner).verified_or_approved.where(
      owner_type: "User",
      owner_id: organizations.pluck(:id)
    ).group_by(&:owner)
    @org_domains = T.let({}, T.nilable(T::Hash[Organization, T::Array[String]]))
    grouped_domains.keys.each do |organization|
      T.must(@org_domains)[organization] = T.must(grouped_domains[organization]).map(&:domain)
    end
    organizations.each { |org| T.must(@org_domains)[org] ||= [] }

    subject = "[GitHub] #{@business.name} enterprise has restricted email notifications"
    premail(
      to: user_email(@user),
      from: github_noreply,
      subject: subject,
    )
  end

  # Public - Notify a user that an enterprise has verified or approved a domain, and therefore
  # admininstrators of enterprise orgs they belong to can now see this user's email address on
  # this domain.
  #
  # user                - user to notify
  # business            - enterprise that has verified or approved the domain
  # organization_logins - list of logins for organizations within the Business that the user
  #                       belongs to
  # domain              - the domain that was just verified or approved
  # state               - the state of the domain, either verified or approved
  def domain_verification_notice(user, business, organization_logins, domain, state)
    @user = user
    @business = business
    @verified_domain = domain
    @organization_logins = organization_logins
    @state = state

    subject = "[GitHub] An owner of the #{@business.safe_profile_name} enterprise just #{@state} the #{@verified_domain} domain"
    premail(
      to: user_email(@user),
      from: github_noreply,
      subject: subject,
    )
  end

  # Public - Notify owners that their enterprise has premium support.
  def premium_support_notice(business)
    @business = business

    subject = "[GitHub] The #{@business.safe_profile_name} enterprise has Premium Support"
    premail(
      from: github,
      reply_to: github_noreply,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  def dormant_users_report(user, business, url, expiry_time)
    @user = user
    @business = business
    @url = url
    @expiry_time = expiry_time

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Your report on Dormant Users is ready to download"
    )
  end

  def dormant_users_report_failed(user, business, url, expiry_time)
    @user = user
    @business = business
    @url = url
    @expiry_time = expiry_time

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Your report on Dormant Users has failed unexpectedly."
    )
  end

  def enterprise_users_report(user, business, url, expiry_time)
    @user = user
    @business = business
    @url = url
    @expiry_time = expiry_time

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Your Enterprise Members report is ready to download"
    )
  end

  # Public: Notify enterprise admins when an audit log stream
  # has been disabled by GitHub staff

  # business - the Business whose stream was disabled
  def audit_log_stream_disabled_stafftools(business, sink_type = "")
    @business = business

    reply_to = github

    subject = ""
    if @business.audit_log_multiple_streaming_endpoint_enabled?
      subject = "[GitHub] The audit log stream streaming to #{sink_type} for #{business.safe_profile_name} has been disabled"
    else
      subject = "[GitHub] The audit log stream for #{business.safe_profile_name} has been disabled"
    end

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  # Public: Notify enterprise admins that there is a problem with
  # their audit log stream and that GitHub staff will disable it
  # if they don't update the configuration

  # business - the Business whose stream is misconfigured
  def audit_log_stream_disabled_warning(business, sink_type = "")
    @business = business

    reply_to = github

    subject = ""
    if @business.audit_log_multiple_streaming_endpoint_enabled?
      subject = "[Action Required] The audit log stream streaming to #{sink_type} for #{business.safe_profile_name} is misconfigured"
    else
      subject = "[Action Required] The audit log stream for #{business.safe_profile_name} is misconfigured"
    end

    premail(
      from: github,
      reply_to: reply_to,
      bcc: business_emails(@business),
      subject: subject,
    )
  end

  # Sent when a user accounts upload has been processed.
  def sync_user_accounts(user, success, upload)
    return if GitHub.single_business_environment?
    @user = user
    @success = success
    @upload = upload
    @url = enterprise_licensing_url(@upload.business)

    premail(
      to: user_email(user),
      subject: "[GitHub] Your GitHub Enterprise Server license usage import #{success ? "is complete" : "failed to process"}"
    )
  end

  # Public - Notify a user that their enterprise cloud license report is ready to download
  #
  # user - user to notify
  # business - enterprise for which the report was generated
  # url - URL to download the report
  # expiry_time - Time when the report will expire (e.g. "This report will expire in @expiry_time")
  def enterprise_cloud_licensing_report(user, business, url, expiry_time)
    @user = user
    @business = business
    @url = url
    @expiry_time = expiry_time

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Your Enterprise Cloud license report is ready to download"
    )
  end

  def prompt_business_to_accept_corporate_tos(business)
    return unless business&.feature_enabled?(:business_on_standard_tos)
    return unless business&.terms_of_service_type == "Standard"

    @business = business
    @slug = business.slug

    premail(
      from: github_noreply,
      bcc: business_emails(@business, include_billing_managers: true),
      subject: "[GitHub] Action required: switch to the GitHub Customer Agreement",
    )
  end

  private

  # Private: Translate a business admin role into a String to be used in an email.
  #
  # Raises ArgumentError if member_role is invalid.
  #
  # member_role - string or symbol for the member's role. Currently :owner, :billing_manager,
  #   :member, or :outside_collaborator
  #
  # Returns String
  def role_for_business_email(member_role)
    case member_role.to_sym
    when Business::OWNER_ROLE
      "an owner"
    when Business::BILLING_MANAGER_ROLE
      "a billing manager"
    when :member
      "a member"
    when :outside_collaborator
      "a collaborator"
    else
      raise ArgumentError, "member_role argument value #{member_role} is invalid"
    end
  end

  def business_emails(business, include_billing_managers: false)
    emails = business.owners.map { |u| user_email(u) }.compact.uniq
    if include_billing_managers
      emails += business.billing_managers.map { |u| user_email(u) }.compact.uniq
    end
    emails
  end

  def organization_emails(organization)
    [organization.profile_email, organization.billing_email, organization.admins.map { |u| user_email(u) }].flatten.compact.uniq
  end

  def removed_org_add_payment_info_or_contact_sales?(business, organization)
    if business.trial? || business.trial_cancelled?
      previous_billing_type = business.organization_invitations.with_status(:confirmed).find_by(
        invitee: organization
      )&.invitee_billing_type
      previous_billing_type == User::BillingDependency::INVOICE_BILLING_TYPE
    else
      false
    end
  end
end
