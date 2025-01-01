# typed: true
# frozen_string_literal: true

class EnterpriseManagedUserMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper

  helper :avatar

  self.mailer_name = "mailers/enterprise_managed_user"

  layout "layouts/primer_layout"

  def self.resolve_tenant(action_name, args)
    case action_name.to_sym
    when :added_as_first_emu_business_admin
      business, * = args
      business
    else
      # fall back to current tenant context if set
      GitHub::CurrentTenant.get
    end
  end

  # Public: Notify the first owner in an EMU enterprise when they have been added.
  #
  # business - The Business.
  # admin_role - A Symbol representing the role of the admin. Currently :owner
  # user - The User that was added.
  #
  # Returns Mail.
  def added_as_first_emu_business_admin(business, admin_role, user)
    email = GitHub.multi_tenant_enterprise? ? user.outbound_email : user.email
    password_reset = PasswordReset.new(
      user: user,
      email: email,
      force: true,
      expires: 7.days.from_now,
    )
    @password_reset_url = password_reset.new_reset_link
    @business = business
    @user = user
    @role_for_email = role_for_business_email(admin_role)
    @password_reset_link = password_reset.link
    @expires = ((password_reset.expires - Time.now) / 1.day).round.to_s
    @enterprise_url = enterprise_url(business)
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: settings_email_preferences_url, text: "Manage your #{GitHub.flavor} email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" }
    ]

    subject = "[GitHub] You’ve been added as #{@role_for_email} of the #{@business.name} enterprise"

    premail(
      from: github,
      to: user_email(@user),
      subject: subject,
    )
  end

  # Public: Notify an EMU user that a repo setup in their user namespace
  # has been unlocked and is viewable to EMU owner
  def user_repository_unlocked(business, user, unlocked_by, repo)
    @business = business
    @unlocked_by = unlocked_by
    @repo_name = repo.name_with_display_owner
    @access_duration = RepositoryUnlock::DEFAULT_EXPIRY
    @user = user

    reply_to = github

    subject = "[GitHub] Access to your #{@repo_name} repository"

    premail(
      from: github,
      to: user_email(@user),
      subject: subject,
    )
  end

  def confirm_claim_email(user, email)
    @email = email
    @code = @email.verification_token

    reply_to = github

    subject = "[GitHub] Claim your email address"

    premail(
      from: github,
      to: user_email(user),
      subject: subject,
    )
  end

  private

  # Private - translate a business admin role into a string to be used in an email
  #
  # member_role - string or symbol for the member's role. Currently :owner
  #
  # Returns: a string. Raises an ArgumentError exception if member_role is invalid
  #
  def role_for_business_email(member_role)
    case member_role.to_sym
    when Business::OWNER_ROLE
      "an owner"
    else
      raise ArgumentError, "member_role argument value #{member_role} is invalid"
    end
  end
end
