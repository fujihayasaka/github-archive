# typed: true
# frozen_string_literal: true

class OrganizationMailer < ApplicationMailer
  extend T::Sig
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper
  include GitHub::RouteHelpers

  self.mailer_name = "mailers/organization"

  helper :application
  helper :organization_trials
  helper :email_link_tracking

  # Some emails here don't use a layout at all, so specify which ones
  # use layouts/primer_layout.
  layout "layouts/primer_layout", only: %i(
    admin_added
    removed_from_org
    remove_outside_collaborator
    domain_verification_notice
    notification_restrictions_enabled
    suspension
    billing_lock
    flagged_as_spammy
  )

  # Public: Resolve the tenant for the given mailer method and args.
  #
  # mail_method - String representing the method on this mailer being called.
  # args - Array of Objects representing the arguments passed to the method being called.
  #
  # Returns nilable Business.
  sig do
    params(
      mail_method: String,
      args: T::Array[Object],
    ).returns(T.nilable(Business))
  end
  def self.resolve_tenant(mail_method, args)
    case mail_method.to_s
    when "removed_from_org"
      if org = args[1]
        T.cast(org, Organization).business
      end
    when "pat_access_request_notice"
      org, * = args
      T.cast(org, Organization).business
    else
      # fall back to current tenant context if set
      GitHub::CurrentTenant.get
    end
  end

  LOOKUP_ORG_OWNER_HELP_DOC_URL = \
    "#{GitHub.help_url}/articles/viewing-people-s-roles-in-an-organization/"

  # Send a notification email to User USER upon removal from Organization ORG.
  # Optionally, include a REASON (a Symbol).
  def removed_from_org(user, org, reason = nil)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @footer_links = footer_links
    @user = user
    @org = org
    @signature = notification_signature(@url)
    @reason = reason&.to_sym
    @lookup_org_owner_help_doc_url = LOOKUP_ORG_OWNER_HELP_DOC_URL

    subject = "[GitHub] You've been removed from the \"#{org.safe_profile_name}\" organization"

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, org).value),
      subject: subject,
      categories: "org,org-remove-member",
    )
  end

  # Send a notification email to User USER upon removal of outside collaborator
  # status from Organization ORG. Include the list of REPOSITORY_NAMES
  # (an Array of Strings) of repositories affected. Optionally include a REASON
  # (a String).
  def remove_outside_collaborator(user, org, repository_names, reason = nil)
    @footer_links = footer_links
    @user = user
    @org = org
    @repository_names = repository_names
    url = org_root_url(@org)
    @signature = notification_signature(url)
    @reason = reason
    @lookup_org_owner_help_doc_url = LOOKUP_ORG_OWNER_HELP_DOC_URL

    subject = "[GitHub] You've been removed from \"#{org.safe_profile_name}\"'s repositories"

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, org).value),
      subject: subject,
      categories: "org,org-remove-outside-collaborator",
    )
  end

  def admin_added(user, organization, adder = nil)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @org = organization
    @url = org_owners_url(@org)
    @signature = notification_signature(@url)

    subject = if !adder || (adder.site_admin? && GitHub.context[:hide_staff_user])
      "[GitHub] You've been made an owner of the \"#{@org.safe_profile_name}\" organization"
    else
      "[GitHub] @#{adder.display_login} made you an owner of the \"#{@org.safe_profile_name}\" organization"
    end

    premail(
      from: github_noreply(@org),
      to: user_email(user, GitHub.newsies.email(user, @org).value),
      subject: subject,
      categories: "org,org-add-admin",
    )
  end

  def application_access_requested(requestor, org, oauth_app, recipient)
    @org_name  = "\"#{org.safe_profile_name}\""
    @requestor = requestor
    @app_name = oauth_app.name
    app_owner = oauth_app.owner
    @app_owner_name = app_owner.safe_profile_name
    @approvals_url = org_application_approval_url(org, oauth_app)

    mail(
      content_transfer_encoding: "quoted-printable",
      from: github_noreply(org),
      to: user_email(recipient, GitHub.newsies.email(recipient, org).value),
      subject: "[GitHub] Third-party application approval request for #{@org_name}",
    )
  end

  def application_access_approved(recipient:, organization:, application:)
    @org_name = "\"#{organization.safe_profile_name}\""
    @app_name = application.name
    @app_owner_name = application.owner.safe_profile_name

    mail(
      content_transfer_encoding: "quoted-printable",
      from: github_noreply(organization),
      to: user_email(recipient, GitHub.newsies.email(recipient, organization).value),
      subject: "[GitHub] #{@org_name} has approved a third-party application that you use",
    )
  end

  def pat_access_request_notice(org)
    @org_name = org.safe_profile_name
    @requests_url = settings_org_personal_access_token_requests_url(org)

    mail(
      from: github_noreply(org),
      bcc: admin_emails(org),
      subject: "[GitHub] Your organization #{@org_name} has received personal access token requests",
    )
  end

  def invited_to_billing_manager_role(invitation, invitation_token = nil)
    # Don't reset token in development so that we can follow the invite link
    invitation.reset_token unless Rails.env.development?

    @invitation = invitation
    @user       = invitation.invitee
    @inviter    = invitation.inviter
    @org        = invitation.organization
    @url        = if invitation.email?
      org_show_pending_billing_manager_invitation_url(@org, invitation_token: invitation.token, via_email: "1")
    else
      org_show_pending_billing_manager_invitation_url(@org, via_email: "1")
    end

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the support address if
    # not.
    if invitation.show_inviter?
      reply_to = user_email(@inviter, allow_private: false)
    end
    reply_to ||= github

    subject = if invitation.show_inviter?
      "[GitHub] @#{@inviter.display_login} has invited you to be a billing manager for the @#{@org.display_login} organization"
    else
      "[GitHub] You're invited to be a billing manager for the @#{@org.display_login} organization"
    end

    mail(
      from: github,
      to: send_to(invitation),
      subject: subject,
      reply_to: reply_to,
      categories: "org,add-billing-manager",
    )
  end

  def failed_two_factor_enforcement(actor, organization, enterprise_team_member_removal_failure: false)
    @actor = actor
    @organization = organization
    @enterprise_team_member_removal_failure = enterprise_team_member_removal_failure

    subject = "[GitHub] Failed to enable and enforce two-factor requirement for \"#{organization.safe_profile_name}\" organization"

    mail(
      from: github_noreply,
      to: user_email(actor, GitHub.newsies.email(actor, organization).value),
      subject: subject,
    )
  end

  # Disclose to an existing org. member (with verified or approved domain emails)
  # that org owners can see their email address(s).
  def domain_verification_notice(user, organization, domain, state)
    @footer_links = footer_links
    @user = user
    @org = organization
    @domain = domain
    @state = state

    subject = "[GitHub] An owner of the \"#{@org.safe_profile_name}\" organization just #{@state} the #{@domain} domain"

    premail(
      to: user_email(@user),
      from: github_noreply(organization),
      subject: subject,
    )
  end

  def notification_restrictions_enabled(user, organization)
    @footer_links = footer_links
    @user = user
    @org = organization
    @email_eligible_domains = @org.email_eligible_domain_urls

    subject = "[GitHub] #{@org.display_login} has restricted email notifications"
    premail(
     to: user_email(user, GitHub.newsies.email(user, @org).value),
     from: github_noreply(@org),
     subject: subject,
   )
  end

  def welcome_enterprise_cloud_trial(actor, organization)
    subject = "Welcome to your GitHub Enterprise trial"
    @organization = organization
    @user = actor
    @new_organization_repository_link = new_org_repository_path(organization)
    @email_source = "ghe_trial_welcome"
    cloud_trial = Billing::EnterpriseCloudTrial.new(@organization)
    @trial_expiry_date = cloud_trial.expires_on&.to_formatted_s(:long)

    premail(
      from: github_noreply,
      to: user_email(actor),
      subject: subject,
    )
  end

  def end_enterprise_cloud_trial(actor, organization)
    return unless organization.plan_trial_active?

    cloud_trial = Billing::EnterpriseCloudTrial.new(organization)
    expires_on = T.must(cloud_trial.expires_on)
    if expires_on > 25.hours.from_now
      delivery_date = (expires_on - 1.day).to_datetime
      OrganizationMailer.end_enterprise_cloud_trial(actor, organization).deliver_later(wait_until: delivery_date)
      return
    end

    subject = "Your GitHub Enterprise trial ends today"
    @organization = organization
    @user = actor
    @new_organization_repository_link = new_org_repository_path(organization)
    @email_source = "ghe_trial_end"

    premail(
      from: github_noreply,
      to: user_email(actor),
      subject: subject,
    )
  end

  def api_applications_endpoints_deprecation(application, time:)
    @application = application
    @org         = application.owner

    @time       = time.to_formatted_s(:deprecation_mailer)

    mail_opts = {
      from: github_noreply(@org),
      bcc: admin_emails(@org),
      subject: "[GitHub API] Deprecation notice for OAuth Application API",
    }

    mail(mail_opts)
  end

  def legacy_integration_event_deprecation(org, app_names)
    @org = org
    @app_names = app_names

    mail_opts = {
      from: github_noreply(@org),
      bcc: admin_emails(@org),
      template_name: :legacy_integration_event_deprecation,
      subject: "[GitHub] FINAL NOTICE: Sunset of GitHub Apps webhook events",
    }

    mail(mail_opts)
  end

  def api_integrations_access_tokens_deprecation(application, time:)
    @application = application
    @org         = application.owner

    @time = time.to_formatted_s(:deprecation_mailer)
    bcc = admin_emails(@org)

    manager_ids = Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: @application.id)
    manager_ids += Permissions::Enumerator.actor_ids_with_permission(action: :manage_all_apps, subject_id: @org.id)
    app_managers = User.where(id: manager_ids).reject { |u| u.suspended? }
    bcc += app_managers.map { |u| user_email(u) }

    mail_opts = {
      from: github_noreply(@org),
      bcc: bcc,
      subject: "[GitHub API] Sunset of Installation Access Token creation API",
    }

    mail(mail_opts)
  end

  sig do
    params(
      organization: T.any(Organization, T::Hash[T.untyped, T.untyped]),
      cancelled_subscription_item_names: T::Array[String],
      tos_reason: T.nilable(String),
      dsa_source: T.nilable(String)
    ).void
  end
  def suspension(organization, cancelled_subscription_item_names, tos_reason = nil, dsa_source = nil)
    @organization = organization
    @cancelled_subscription_item_names = cancelled_subscription_item_names
    @tos_reason = tos_reason
    @dsa_source = dsa_source
    @dsa_source_text = DsaExplanations.email_partial_for_dsa_source(dsa_source)
    @dsa_explanation_text = DsaExplanations.email_partial_for_tos_reason(tos_reason)

    bcc = admin_emails(@organization)
    mail_opts = {
      from: github_noreply,
      bcc: bcc,
      subject: "[GitHub] Organization suspended"
    }

    # Only send if there are admins to email
    premail(mail_opts) if bcc.size > 0
  end

  def billing_lock(organization, cancelled_subscription_item_names)
    @organization = organization
    @cancelled_subscription_item_names = cancelled_subscription_item_names

    bcc = admin_emails(@organization)
    mail_opts = {
      from: github_noreply,
      bcc: bcc,
      subject: "[GitHub] Payment Issues for Organization"
    }

    # Only send if there are admins to email
    premail(mail_opts) if bcc.size > 0
  end

  def flagged_as_spammy(organization, tos_reason, dsa_source)
    return unless dsa_source.present?

    @organization = organization
    @tos_reason = tos_reason
    @dsa_source = dsa_source
    @dsa_source_text = DsaExplanations.email_partial_for_dsa_source(dsa_source)
    @dsa_explanation_text = DsaExplanations.email_partial_for_tos_reason(tos_reason)

    bcc = admin_emails(@organization)
    mail_opts = {
      from: github_noreply,
      bcc: bcc,
      subject: "[GitHub] Organization flagged"
    }
    # Only send if there are admins to email
    premail(mail_opts) if bcc.size > 0
  end

  private

  def send_to(invitation)
    if invitation.email?
      invitation.email
    else
      user_email(@user, GitHub.newsies.email(@user, @org).value)
    end
  end
end
