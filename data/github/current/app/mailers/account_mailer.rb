# typed: true
# frozen_string_literal: true

class AccountMailer < ApplicationMailer
  extend T::Sig
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper

  # Necessary for the `settings_app_transfer_url` method
  include GitHub::RouteHelpers

  self.mailer_name = "mailers/account"

  helper :application
  helper :avatar
  helper :comments
  helper :email_link_tracking

  ACCOUNT_SECURITY_LAYOUT_ACTIONS = [
    :configure_sms_fallback,
    :email_address_added,
    :email_address_removed,
    :oauth_authorization_notification,
    :remove_sms_fallback_for_user,
    :two_factor_brute_force,
    :two_factor_recover,
    :unexpected_sign_in,
    :unexpected_incomplete_sign_in,
    :username_and_password_compromised,
    :weak_password_warning,
    :two_factor_requirement_initial_notification_2fa_enabled,
    :two_factor_requirement_initial_notification_2fa_disabled,
    :two_factor_requirement_warning,
    :two_factor_requirement_now_enforced,
    :security_key_added,
    :security_key_removed,
    :recovery_codes_viewed
  ]

  PRIMER_LAYOUT_ACTIONS = [
    :archive_org,
    :attribution_invitation_notification,
    :billing_lock,
    :blocked_by_org,
    :delete_org,
    :delete_user,
    :flagged_as_spammy,
    :invited_to_org,
    :invited_to_org_by_email,
    :org_invitation_canceled,
    :organization_email_verification,
    :passkey_added,
    :passkey_removed,
    :programmatic_access_created_notice,
    :programmatic_access_expiration_warning_notice,
    :programmatic_access_expired_notice,
    :programmatic_access_regenerated_notice,
    :programmatic_access_revoked_notice,
    :programmatic_access_approved_notice,
    :programmatic_access_denied_notice,
    :suspension,
    :welcome,
    :two_factor_requirement_inform_admin,
  ]

  layout proc {
    T.bind(self, AccountMailer)

    case action_name.to_sym
    when *PRIMER_LAYOUT_ACTIONS
      "layouts/primer_layout"
    when :invited_to_repo_by_email
      "repository/collab_email_layout"
    when *ACCOUNT_SECURITY_LAYOUT_ACTIONS
      "account/security"
    end
  }

  def self.resolve_tenant(action_name, args)
    case action_name.to_sym
    when :pat_expiry_notice,
      :pat_expired_notice
      oauth_access, * = args
      Business.find_by(id: oauth_access.user.business_id)
    when :oauth_authorization_notification
      arg1, * = args
      arg1 => { authorization: }
      Business.find_by(id: authorization.user.business_id)
    else
      # fall back to current tenant context if set
      GitHub::CurrentTenant.get
    end
  end

  def organization_email_verification(email, requested_by:, redirect: nil, from_profile_email_verify: nil)
    @requested_by = requested_by
    @from_profile_email_verify = from_profile_email_verify
    @organization = @from_profile_email_verify ? email.organization : email.user
    @email        = email

    if @from_profile_email_verify
      @cta_url  = organization_confirm_profile_email_url(@organization,
                                                        @email,
                                                        @email.verification_token,
                                                        redirect: redirect)
    else
      @cta_url  = organization_confirm_verification_email_url(@organization,
                                                            @email,
                                                            @email.verification_token,
                                                            redirect: redirect)
    end

    @cta_tracking_url = ga_campaign_url(@cta_url,
                                        source: "verification-email",
                                        medium: "email",
                                        campaign: "github-email-verification",
                                        content: "html")

    premail(
      to: user_email(@organization, email.to_s),
      subject: "[GitHub] Please verify an email address for #{@organization}.",
    )
  end

  def archive_org(options)
    @org_login = options[:org_login]
    @archiver = options[:archiver]
    @by_site_admin = options[:by_site_admin]

    recipients = options[:recipients]

    premail \
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Organization #{@org_login} archived"
  end

  def download_everything(user, url)
    @user = user
    @url = url

    mail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Your data export is ready to download",
    )
  end

  def delete_user(options)
    @user = options[:user_name]

    recipients = options[:recipients]

    premail \
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Account deletion"
  end

  def delete_org(options)
    @org_login = options[:org_login]
    @paid_account = options[:paid_account]
    @deleter = options[:deleter]

    recipients = options[:recipients]

    premail \
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Organization deletion"
  end

  def delete_private(options)
    @user_login   = options[:user_login]
    @user_email   = options[:user_email]
    @deleter      = options[:deleter]
    @transactions = options[:transactions]
    @repos        = options[:repos]

    mail(
      to: bcc_log,
      subject: "[GitHub] Account deletion",
    )
  end

  # Sent when a public key is added to a user account.
  def public_key_added(key)
    @user = key.user
    @key = key

    mail(
      to: user_email(key.user),
      subject: "[GitHub] A new SSH authentication public key was added to your account",
    )
  end

  # Sent when a public key is updated.
  def public_key_updated(key)
    @user = key.user
    @key = key

    mail(
      to: user_email(key.user),
      subject: "[GitHub] An SSH authentication public key associated with your account was updated",
    )
  end

  # Sent when a git signing public key is added to a user account.
  def git_signing_ssh_public_key_added(key)
    @user = key.user
    @key = key

    mail(
      to: user_email(key.user),
      subject: "[GitHub] A new SSH git commit signing public key was added to your account",
    )
  end

  # Sent when a user changes her password.
  def password_changed(user, reason)
    @user = user
    @raw_address = user.email

    to = @user.primary_user_email
    bcc = @user.emails.notifiable - [to]

    @explanation = case reason
    when "changed"
      "has changed"
    when "reset"
      "was reset"
    else
      raise ArgumentError, "Expected reason to be 'changed' or 'reset' but was #{reason}"
    end

    mail(
      to: user_email(@user, to.to_s),
      bcc: bcc.map { |email| user_email(@user, email.to_s) },
      subject: "[GitHub] Your password #{@explanation}",
    )
  end

  def two_factor_enable(credential, reconfiguring)
    @user = credential.user
    @credential = credential
    @reconfiguring = reconfiguring

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_enable,
      subject: "[GitHub] Please download your two-factor recovery codes",
    )
  end

  def two_factor_disable(user)
    @user = user

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_disable,
      subject: "[GitHub] Two-factor authentication disabled",
    )
  end

  def two_factor_configure_factor(user, factor, reconfiguring: false)
    @user = user
    @factor_display_name = factor
    @reconfiguring = reconfiguring

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_configure_factor,
      subject: "[GitHub] New two-factor authentication factor configured"
    )
  end

  def two_factor_disable_factor(user, factor, updated_fallback: false)
    @user = user
    @factor_display_name = factor
    @updated_fallback = updated_fallback

    subject_type = updated_fallback ? "updated" : "disabled"

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_disable_factor,
      subject: "[GitHub] Two-factor authentication factor #{subject_type}"
    )
  end

  # An email sent to the user's password reset emails when a recovery code is
  # used to access a 2FA-enabled account
  #
  # user: the owner of the TwoFactorCredential
  def two_factor_recover(user, remaining_codes_count)
    @remaining_codes_count = remaining_codes_count
    @user = user
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A recovery code was used to access your account",
      template_name: :two_factor_recover,
    )
  end

  def recovery_codes_viewed(user, viewed_at)
    @user = user
    @viewed_at = viewed_at
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] Your two-factor authentication recovery codes were viewed",
      template_name: :recovery_codes_viewed,
    )
  end

  def configure_sms_fallback(user, new_number, edited_existing: true, registering_fallback_no_longer_supported: true)
    @user = user
    @new_number = new_number
    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :configure_sms_fallback,
      subject: "[GitHub] A backup phone number on your account has been updated",
    )
  end

  def remove_sms_fallback_for_user(user, previous_number)
    @user = user
    @previous_number = previous_number

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :remove_sms_fallback,
      subject: "[GitHub] A backup phone number has been removed from your account",
    )
  end

  def remove_duplicate_sms_number(user, number)
    @user = user
    @number = number[-4, 4] # show last 4 digits of phone number
    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :remove_duplicate_sms_number,
      subject: "[GitHub] A backup phone number has been removed from your account",
    )
  end

  def security_key_added(user, nickname)
    @user = user
    @nickname = nickname

    mail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] A security key was added to your account",
    )
  end

  def security_key_removed(user, nickname)
    @user = user
    @nickname = nickname

    mail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] A security key was removed from your account",
    )
  end

  def passkey_added(user, useragent_nickname)
    @user = user
    @useragent_nickname = useragent_nickname
    @two_factor_enabled = user.two_factor_authentication_enabled?

    mail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] A passkey was added to your account",
    )
  end

  def passkey_removed(user, nickname)
    @user = user
    @nickname = nickname

    mail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] A passkey was removed from your account",
    )
  end

  def repository_transfer(xfer)
    @repo      = xfer.repository
    @requester = xfer.requester
    @target    = xfer.target
    @token     = xfer.token
    @new_name  = xfer.new_name
    @private_repo_on_free_plan = @target.free_plan? && @repo.private?
    @private_collaborator_seats = @target.plan_limit(:collaborators, visibility: :private)
    @show_rulesets_and_protected_branches_warning = @repo.protected_branches.any? || @repo.rulesets.any?

    recipients = user_or_admin_recipients(@target)

    mail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "[GitHub] Repository transfer from @#{@requester.display_login} (#{@repo.name_with_display_owner})",
    )

    GlobalInstrumenter.instrument("repository.transfer_email", {
      repository: xfer.repository,
      email_reason: "transfer_requested",
      user: xfer.requester,
      target_id: xfer.target_id,
    })
  end

  def immediate_repository_transfer(repository, requester, target, nwo_was)
    @repo      = repository
    @requester = requester
    @target    = target
    @nwo_was   = nwo_was

    recipients = user_or_admin_recipients(@target)

    mail(
        from: github_noreply,
        to: recipients[:to],
        bcc: recipients[:bcc],
        subject: "[GitHub] Repository transfer from @#{@requester.display_login} (#{@nwo_was})",
    )

    GlobalInstrumenter.instrument("repository.transfer_email", {
      repository: repository,
      email_reason: "immediate_transfer",
      user: requester,
      target_id: target.id,
    })
  end

  def invited_to_org(invitation, invitation_token = nil)
    @invitation       = invitation
    @invitation_token = invitation_token
    @user             = invitation.invitee
    @inviter          = invitation.inviter
    @org              = invitation.organization
    @login_to_block   = invitation.show_inviter? ? @inviter.display_login : @org.display_login
    @footer_links     = footer_links

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the noreply address if
    # not.
    reply_to = if invitation.show_inviter?
      user_email(invitation.inviter, allow_private: false) || github_noreply(invitation.inviter)
    else
      github_noreply
    end

    subject = if invitation.show_inviter?
      "[GitHub] @#{@inviter.display_login} has invited you to join the @#{@org.display_login} organization"
    else
      "[GitHub] You’re invited to join the @#{@org.display_login} organization"
    end

    premail(
      from: github_noreply,
      reply_to: reply_to,
      to: user_email(@user),
      subject: subject,
    )
  end

  def invited_to_org_by_email(invitation, invitation_token = nil)
    # ensure token displayed on-screen in local dev after invite is sent remains valid
    invitation.reset_token unless Rails.env.development?

    @invitation       = invitation
    @email            = invitation.email
    @inviter          = invitation.inviter
    @org              = invitation.organization
    @invitation_token = invitation.token
    @login_to_block   = invitation.show_inviter? ? @inviter.display_login : @org.display_login
    @footer_links     = footer_links

    # Use the inviter's email address as the reply-to email if the inviter
    # exists and has a valid email address. Fall back to the noreply address if
    # not.
    reply_to = if invitation.show_inviter?
      user_email(invitation.inviter, allow_private: false) || github_noreply(invitation.inviter)
    else
      github_noreply
    end

    subject = if invitation.show_inviter?
      "[GitHub] @#{@inviter.display_login} has invited you to join the @#{@org.display_login} organization"
    else
      "[GitHub] You're invited to join the @#{@org.display_login} organization"
    end

    premail(
      from: github_noreply,
      reply_to: reply_to,
      to: @email,
      subject: subject,
    )
  end

  def org_invitation_canceled(invitation)
    @invitation = invitation
    @email = @invitation.email? ? @invitation.email : user_email(@invitation.invitee)
    @org = @invitation.organization

    premail(
      from: github_noreply,
      to: @email,
      subject: "[GitHub] Your invitation to #{@org.display_login} has been canceled",
    )
  end

  def org_invitation_failed(user, org, failures)
    @user = user
    @org = org
    begin
      @failures = JSON.parse(failures)
    rescue JSON::ParserError # Raise a clean error so we don't leak PII
      raise JSON::ParserError.new
    end
    @email_source = "org_invitation_failed"

    if @failures.length > 1
      subject = "We weren’t able to send some of your invitations"
    else
      subject = "One of your invitations didn't reach its recipient"
    end

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: subject,
    )
  end

  def blocked_by_org(org, blocked_user, content, duration_string)
    @login = blocked_user.safe_profile_name
    @org = org
    @content_url = content_url(content)
    @coc_url = coc_url(content)
    subject = "[GitHub] You have been blocked from #{@org.display_login}"

    if duration_string
      @duration = duration_string
      subject += @duration
    end

    premail(
      from: github_noreply,
      reply_to: github,
      to: user_email(blocked_user),
      subject: subject,
    )
  end

  # Public: Notify a user that their audit log export is complete
  #
  # user - the User who initiated the export
  # target - the User, Org, or Business whose audit log is being exported
  def audit_log_download_available(user, target)
    @user = user
    @target = target

    reply_to = github

    case @target
    when User
      if @target.organization?
        subject = "Your audit log export is ready to download"
        @header_content = "Your audit log export for the #{@target.name} organization is available to download."
        @title_content = "Audit log export available to download"
        @body_content = "Your audit log export for the #{@target.name} organization is available to download. Please visit your export history page to download."
        @url = org_audit_log_export_logs_url(@target)
      else
        subject = "Your security log export is ready to download"
        @header_content = "Your security log export is available to download."
        @title_content = "Security log export available to download"
        @body_content = "Your security log export is available to download. Please visit your export history page to download."
        @url = settings_user_audit_log_export_logs_url
      end
    when Business
      subject = "Your audit log export is ready to download"
      @header_content = "Your audit log export for the #{@target.name} enterprise is available to download."
      @title_content = "Audit log export available to download"
      @body_content = "Your audit log export for the #{@target.name} enterprise is available to download. Please visit your export history page to download."
      @url = settings_audit_log_export_logs_enterprise_url(@target)
    else
      raise ArgumentError, "target type is unknown"
    end

    premail(
      from: github,
      reply_to: reply_to,
      bcc: user_email(@user),
      subject: subject,
    )
  end

  private def content_url(content)
    # If the content has been deleted we'll likely get an ActiveJob::DeserializationError
    # instead of making it this far, but it seems prudent to check.
    return if content.nil? || content.destroyed?
    GitHub.url + content.async_path_uri.sync.to_s
  end

  private def coc_url(content)
    return if content.nil? || content.destroyed?
    content.repository&.code_of_conduct&.url
  end

  def application_transfer_request(xfer)
    @application = xfer.application
    @requester   = xfer.requester
    @target      = xfer.target
    @xfer        = xfer

    mail(
      from: github_noreply,
      bcc: admin_emails(@target),
      subject: "[GitHub] OAuth Application transfer from @#{@requester.display_login} (#{@application.name})",
    )
  end

  def integration_transfer_request(xfer)
    @integration = xfer.integration
    @requester   = xfer.requester
    @target      = xfer.target
    @xfer        = xfer

    mail(
      from: github_noreply,
      bcc: admin_emails(@target),
      subject: "[GitHub] Integration transfer from @#{@requester.display_login} (#{@integration.name})",
    )
  end

  def legacy_reply_token_bounce(email)
    mail(
      from: github_noreply,
      to: email.from_address,
      subject: "GitHub was unable to receive your email",
    )
  end

  # An email sent to the user when they verify their first email address after signing up.
  # - Sent to users with a transactional email preference.
  # - Users with a marketing email preference receive the welcome series via MailChimp instead.
  #
  # email - a UserEmail
  #
  def welcome(email)
    @user = email.user
    @footer_links = footer_links

    premail(
      from: github_noreply,
      to: user_email(@user, email.to_s),
      subject: "[GitHub] Welcome to GitHub, @#{@user.display_login}!",
    )
  end

  # An email sent to the user when they add an email address to their account.
  # Avoids sending an email to the newly added address since an account without
  # any confirmed emails would include the newly created address in
  # #account_related_emails
  #
  # email - a UserEmail
  def email_address_added(email)
    # no notifications are sent for EMU users
    return if email.user.is_enterprise_managed?

    @user = email.user
    @email = email

    # Remove the primary address (to) and the recently added address
    # since it's receiving a verification email already.
    bcc = @user.account_related_emails.map(&:to_s) - [email.to_s, @user.email]

    mail(
      to: user_email(@user),
      bcc: bcc.map { |address| user_email(@user, address.to_s) },
      subject: "[GitHub] An email address was added to your account.",
    )
  end

  # An email sent to the user when an email addressed is removed from an
  # account. We deliver to the address that was just removed and we BCC all
  # account-related emails.
  #
  # user - a User record
  # email - a String
  def email_address_removed(user, email)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @email = email

    mail(
      # Deliver to recently removed address
      to: user_email(@user, @email),
      # BCC all other account-related emails
      bcc: @user.account_related_emails.map { |address| user_email(@user, address.to_s) },
      subject: "[GitHub] An email address was removed from your account.",
     )
  end

  # An email sent to the user when an email addressed is unlinked from an
  # account. We deliver to the address that was just removed and we BCC all
  # account-related emails. This is done as part of the of the "Email Unlink"
  # flow on 2FA locked accounts.
  #
  # user - a User record
  # email - a String
  def email_address_unlinked(user, email)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @email = email

    mail(
      # Deliver to recently removed address
      to: user_email(@user, @email),
      # BCC all other account-related emails
      bcc: @user.account_related_emails.map { |address| user_email(@user, address.to_s) },
      from: github_noreply,
      subject: "[GitHub] An email address was unlinked from your account.",
     )
  end

  def two_factor_brute_force(user)
    @user = user

    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] Having trouble signing in with two-factor authentication?",
      template_name: :two_factor_brute_force,
    )
  end

  def api_applications_endpoints_deprecation(application, time:)
    @application = application
    @user = application.owner

    @time = time.to_formatted_s(:deprecation_mailer)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :api_applications_endpoints_deprecation,
      subject: "[GitHub API] Deprecation notice for OAuth Application API",
    )
  end

  def pat_expiry_notice(oauth_access)
    @oauth_access = oauth_access
    @user = oauth_access.user
    @token_type = "personal access token#{" (classic)" if @user.patsv2_enabled?}"

    @reset_link = "#{GitHub.url}/settings/tokens/#{@oauth_access.id}/regenerate"

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :pat_expiry_notice,
      subject: "[GitHub] Your #{@token_type} is about to expire",
    )
  end

  def pat_expired_notice(oauth_access)
    @oauth_access = oauth_access
    @user = oauth_access.user
    @token_type = "personal access token#{" (classic)" if @user.patsv2_enabled?}"

    @reset_link = "#{GitHub.url}/settings/tokens/#{@oauth_access.id}/regenerate"

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :pat_expired_notice,
      subject: "[GitHub] Your #{@token_type} has expired",
    )
  end

  def programmatic_access_created_notice(access)
    @access = access
    @user = access.owner

    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_created_notice,
      subject: "[GitHub] A fine-grained personal access token has been added to your account",
    )
  end

  def programmatic_access_regenerated_notice(access)
    @access = access
    @user = access.owner

    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A fine-grained personal access token has been regenerated for your account",
      template_name: :programmatic_access_regenerated_notice,
    )
  end

  def programmatic_access_expiration_warning_notice(access, remaining_days = "1d")
    @remaining_days = ProgrammaticAccess::EXPIRATION_WARNING_THRESHOLDS[remaining_days]
    return unless @remaining_days

    @access = access
    @user = @access.owner

    @reset_link = edit_regenerate_user_access_token_url(@access)
    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_expiration_warning_notice,
      subject: "[GitHub] Your fine-grained personal access token is about to expire",
    )
  end

  def programmatic_access_expired_notice(access)
    @access = access
    @user = @access.owner

    @reset_link = edit_regenerate_user_access_token_url(@access)
    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_expired_notice,
      subject: "[GitHub] Your fine-grained personal access token has expired",
    )
  end

  def programmatic_access_revoked_notice(accesses, owner, target)
    @accesses = accesses
    @user = owner
    @target = target

    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_revoked_notice,
      subject: "[GitHub] #{@target.display_login} access has been revoked on your fine-grained personal access tokens",
    )
  end

  def programmatic_access_approved_notice(accesses, owner, target)
    @accesses = accesses
    @user = owner
    @target = target

    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_approved_notice,
      subject: "[GitHub] #{@target.display_login} access has been approved on your fine-grained personal access tokens",
    )
  end

  def programmatic_access_denied_notice(accesses, owner, target, reason = nil)
    @accesses = accesses
    @user = owner
    @target = target
    @reason = reason

    @footer_links = account_security_footer_links

    premail_to_primary_bcc_remaining_account_related_emails(
      template_name: :programmatic_access_denied_notice,
      subject: "[GitHub] #{@target.display_login} access has been denied on your fine-grained personal access tokens",
    )
  end

  def legacy_integration_event_deprecation(user, app_names)
    @user = user
    @app_names = app_names

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :legacy_integration_event_deprecation,
      subject: "[GitHub] FINAL NOTICE: Sunset of GitHub Apps webhook events",
    )
  end

  def api_integrations_access_tokens_deprecation(application, time:)
    @application = application
    @user = application.owner

    @time = time.to_formatted_s(:deprecation_mailer)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :api_integrations_access_tokens_deprecation,
      subject: "[GitHub API] Sunset of GitHub Apps installation token creation API",
    )
  end

  private def unexpected_sign_in_explanation(reason)
    case reason
    when "unrecognized_location", "unrecognized_device_and_location", "no_records_exist"
      "location of the sign in"
    when "unrecognized_device"
      raise NotImplementedError, "Notifications for unknown devices are disabled"
    else
      raise ArgumentError, "Unknown unexpected login notification reason"
    end
  end

  # Notify users of logins from unexpected locations.
  #
  # authentication_record: the record that was created after a correct
  #  password was supplied.
  def unexpected_sign_in(authentication_record)
    @user = authentication_record.user
    @authentication_record = authentication_record
    @reason = unexpected_sign_in_explanation(authentication_record.flagged_reason)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :unexpected_sign_in,
      subject: "[GitHub] Please review this sign in",
    )
  end

  def weak_password_warning(user, client, user_agent: nil, deadline: nil)
    @user = user
    @user_agent = user_agent
    @deadline = deadline
    @client = case client
    when "git"
      "Git"
    when "api"
      "the API"
    when "gist"
      "Gist"
    when "wiki"
      "GitHub Wikis"
    when "web"
      "GitHub.com"
    else
      raise ArgumentError.new("unknown client")
    end

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :weak_password_warning,
      subject: "[GitHub] Please change your password",
     )
  end

  # Notify a user that their session was revoked
  # because of data that was shared in a dump that is available to criminal actors.
  #
  # user: the user that owns the session that was revoked.
  def compromised_session_revoked(user)
    @user = user
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "Important Information About Your GitHub Account",
      template_name: :compromised_session_revoked,
    )
  end

  # Notify grandfathered SMS users of backup sms registration deprecation.
  #
  # user: the grandfathered user that has 2 SMS registrations.
  def backup_sms_deprecation(user)
    @user = user
    primary_email = @user.email
    bcc = @user.account_related_emails.map(&:to_s) - [primary_email]
    mail(
      {
        # the `from` address is hardcoded instead of using `from: github_noreply` because the mailer is sent via a transition
        # with the transition hosts that won't necessarily be github.com.
        from: %{"GitHub" <noreply@github.com>},
        to: user_email(@user, primary_email),
        bcc: bcc.map { |email| user_email(@user, email) },
        subject: "Changes to the 2FA settings on your GitHub account",
        template_name: :backup_sms_deprecation,
      }
    )
  end

  # Notify users of a compromise containing their username and password
  #
  # user: The compromised user
  def username_and_password_compromised(user)
    @user = user
    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :username_and_password_compromised,
      subject: "[GitHub] Please change your password",
    )
  end

  # Initial notification for users that 2FA will soon be required for their account
  #
  # user: The user to notify
  def two_factor_requirement_initial_notification_2fa_enabled(user)
    @user = user
    @two_factor_required_by = get_rounded_2fa_requirement_time(user)
    primary_email = @user.email
    mail({
      to: user_email(@user, primary_email),
      subject: "[GitHub 2FA] You will no longer be able to disable 2FA for your GitHub account, #{@user.display_login}",
      template_name: :two_factor_requirement_initial_notification_2fa_enabled
    })
  end

  # Initial notification for users that 2FA will soon be required for their account
  #
  # user: The user to notify
  def two_factor_requirement_initial_notification_2fa_disabled(user)
    @user = user
    @two_factor_required_by = get_rounded_2fa_requirement_time(user)

    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[ACTION REQUIRED] Your GitHub account, #{user.display_login}, will soon require 2FA",
      template_name: :two_factor_requirement_initial_notification_2fa_disabled,
    )
  end

  # Notify users that 2FA will soon be required for their account
  #
  # user: The user to notify
  def two_factor_requirement_warning(user)
    @user = user
    @two_factor_required_by = get_rounded_2fa_requirement_time(user)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_requirement_warning,
      subject: "[ACTION REQUIRED] Your GitHub account, #{user.display_login}, will soon require 2FA",
    )
  end

  # Notify users that 2FA is now required for their account
  #
  # user: The user to notify
  def two_factor_requirement_now_enforced(user)
    @user = user
    @two_factor_required_by = get_rounded_2fa_requirement_time(user)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_requirement_now_enforced,
      subject: "[ACTION REQUIRED] Your GitHub account, #{user.display_login}, now requires 2FA",
    )
  end

  # Notify org/enterprise admins that over 50 users in their entities are going to be flagged for 2FA enrollment
  # This mailer can be triggered by manual transition before bulwark 2FA cohort batch enrollment
  def two_factor_requirement_inform_admin(admin_user, entity_name, is_org, user_count, user_2fa_enabled_count)
    @user = admin_user
    @is_org = is_org == 0 ? false : is_org
    @entity_name = entity_name
    @entity_type = @is_org ? "organization" : "enterprise"
    @user_count = user_count
    @user_2fa_enabled_count = user_2fa_enabled_count

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :two_factor_requirement_inform_admin,
      subject: "Users in your #{@entity_type} will soon be required to enable 2FA",
    )
  end

  # Notify users of partial two factor sign ins unexpected locations. Use the
  # email addresses at the time of sign in to prevent an attacker from changing
  # the email addresses on the account before the notification is delivered.
  #
  # authentication_record: the record that was created after a correct
  #   password was supplied.
  # emails: an array of email address strings that represent the notifiable
  #   addresses at the time of sign in.
  def unexpected_incomplete_sign_in(authentication_record, primary_email, bcc_emails)
    @user = authentication_record.user
    @reason = unexpected_sign_in_explanation(authentication_record.flagged_reason)
    @authentication_record = authentication_record

    mail(
      to: user_email(@user, primary_email),
      bcc: bcc_emails.map { |address| user_email(@user, address.to_s) },
      subject: "[GitHub] Please review this attempt to sign in",
     )
  end

  # An email sent to the user's admin emails when a third party application
  # is granted access to non-private scopes
  #
  # authorization - the newly created/update OAuthAuthorization record
  # added_scopes - newly authorized, non-public scopes
  # user - the user that created the OAuthAuthorization
  def oauth_authorization_notification(authorization:, added_scopes:, previous_scopes:, is_new_record:, is_regenerated:)
    @authorization = authorization
    @user = @authorization.user
    @current_scopes = authorization.scopes
    @previous_scopes = previous_scopes
    @added_scopes = added_scopes

    if authorization.personal_access_authorization?
      @token_type = "personal access token#{" (classic)" if @user.patsv2_enabled?}"
      if is_new_record
        new_personal_access_token
      elsif is_regenerated
        regenerated_personal_access_token
      else
        updated_personal_access_token
      end
    else
      @application_owner = if @authorization.application.owned_or_operated_by_github?
        "first-party GitHub"
      else
        "third-party"
      end
      if is_new_record
        new_oauth_authorization
      else
        updated_oauth_authorization
      end
    end
  end

  def blocked_from_org_notification(user, org, comment)
    premail(
      to: user_email(user),
      subject: "[GitHub] An organization has blocked you",
    )
  end

  def attribution_invitation_notification(invitation)
    @source = invitation.source
    @target = invitation.target
    @inviter = invitation.creator
    @org = invitation.owner

    premail(
      to: user_email(@target),
      subject: "[GitHub] You have been invited to claim contributions in #{@org.display_login}",
    )
  end

  sig do
    params(
      user: T.any(User, User::BillingDependency, T::Hash[T.untyped, T.untyped]),
      cancelled_subscription_item_names: T::Array[String],
      tos_reason: T.nilable(String),
      dsa_source: T.nilable(String)
    ).void
  end
  def suspension(user, cancelled_subscription_item_names, tos_reason = nil, dsa_source = nil)
    @user = user
    @cancelled_subscription_item_names = cancelled_subscription_item_names
    @tos_reason = tos_reason
    @dsa_source = dsa_source
    @dsa_source_text = DsaExplanations.email_partial_for_dsa_source(dsa_source)
    @dsa_explanation_text = DsaExplanations.email_partial_for_tos_reason(tos_reason)

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Account suspended"
    )
  end

  def billing_lock(user, cancelled_subscription_item_names)
    @user = user
    @cancelled_subscription_item_names = cancelled_subscription_item_names

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Payment Issues for Account"
    )
  end

  def flagged_as_spammy(user, tos_reason, dsa_source)
    return unless dsa_source.present?

    @user = user
    @tos_reason = tos_reason
    @dsa_source = dsa_source
    @dsa_source_text = DsaExplanations.email_partial_for_dsa_source(dsa_source)
    @dsa_explanation_text = DsaExplanations.email_partial_for_tos_reason(tos_reason)

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: "[GitHub] Account flagged"
    )
  end

  private def new_oauth_authorization
    @scopes_message = scopes_message
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A #{@application_owner} OAuth application has been added to your account",
      template_name: :new_oauth_authorization,
    )
  end

  private def updated_oauth_authorization
    @previous_scopes_message = previous_scopes_message
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A previously authorized #{@application_owner} OAuth application has been granted additional scopes",
      template_name: :updated_oauth_authorization,
    )
  end

  private def new_personal_access_token
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A #{@token_type} has been added to your account",
      template_name: :new_personal_access_token,
    )
  end

  private def regenerated_personal_access_token
    @scopes_message = scopes_message
    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A #{@token_type} has been regenerated for your account",
      template_name: :regenerated_personal_access_token,
    )
  end

  private def updated_personal_access_token
    @previous_scopes_message = previous_scopes_message

    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] A #{@token_type} has been granted additional scopes",
      template_name: :updated_personal_access_token,
    )
  end

  private def scopes_message
    scopes = Array(@current_scopes)

    if scopes.empty?
      "access to public information (read-only)"
    else
      "#{html_safe_to_sentence(scopes)} #{pluralize_without_number(scopes, "scope")}"
    end
  end

  private def previous_scopes_message
    if @previous_scopes.any?
      "had #{@previous_scopes.to_sentence} #{pluralize_without_number(@previous_scopes.count, "scope")}"
    else
      "did not have any scopes"
    end
  end

  private def footer_links
    links = []
    if defined?(@org) && @org.present? && defined?(@invitation_token)
      links << {
        url: show_org_invitation_opt_out_confirmation_url(@org, invitation_token: @invitation_token), text: "Opt out of future invitations from this organization"
      }
    end
    links + super
  end

  private def account_security_footer_links
    [
      { url: settings_user_audit_log_url, text: "Your security audit log" },
      { url: contact_url, text: "Contact support" }
    ]
  end

  private def get_rounded_2fa_requirement_time(user)
    if user.two_factor_requirement_metadata.required_by.min < 30
      user.two_factor_requirement_metadata.required_by.beginning_of_hour.to_formatted_s(:deprecation_mailer)
    else
      (user.two_factor_requirement_metadata.required_by + 1.hour).beginning_of_hour.to_formatted_s(:deprecation_mailer)
    end
  end

  module Serializers
    def self.archive_org(org, admins, actor, by_site_admin: false)
      {
        org_login: org.display_login,
        archiver: actor,
        recipients: ApplicationMailer::Helpers.build_admin_recipients_list(org, admins),
        by_site_admin: by_site_admin,
      }
    end

    def self.delete_org(org, admins)
      {
        org_login: org.display_login,
        paid_account: org.plan.paid?,
        deleter: org.deleted_by,
        recipients: ApplicationMailer::Helpers.build_admin_recipients_list(org, admins)
      }
    end

    def self.delete_private(user)
      user         = user
      deleter      = user.user? ? user.to_s : user.deleted_by.to_s
      transactions = user.transactions.map do |transaction|
        old = transaction.old_plan.blank? ? "" : "#{transaction.old_plan.display_name.capitalize} -> "
        "#{transaction.timestamp} - #{transaction.action.camelize.upcase} #{old}#{transaction.current_plan.display_name.capitalize}"
      end
      repos = user.repositories.map do |repo|
        "#{user.display_login}/#{repo}: #{repo.network_id}/#{repo.id}"
      end
      {
        user_login: user.display_login,
        user_email: user.email,
        deleter: deleter,
        transactions: transactions,
        repos: repos
      }
    end

    def self.delete_user(user, admins)
      {
        user_name: user.name,
        recipients: ApplicationMailer::Helpers.build_admin_recipients_list(user, admins)
      }
    end
  end
end
