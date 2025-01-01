# typed: true
# frozen_string_literal: true

# Decorator object around User to validate and create a
# "StealthEmail".  A StealthEmail is an actual UserEmail object
# that is used as the git author email from github.com when a user
# elects to keep their primary email private.
class StealthEmail
  attr_reader :user
  delegate :display_login, to: :user
  delegate :emails, to: :user

  STEALTH_EMAIL_REGEX = /\A(\d+)\+[a-zA-Z0-9\-_]+(#{Regexp.escape(Bot::LOGIN_SUFFIX)})?@#{Regexp.quote(GitHub.stealth_email_host_name)}\z/
  OLD_STEALTH_EMAIL_REGEX = /\A([a-zA-Z0-9\-]+(#{Regexp.escape(Bot::LOGIN_SUFFIX)})?)@#{Regexp.quote(GitHub.stealth_email_host_name)}\z/
  STEALTH_EMAIL_HOST_NAME_REGEX = /\A.+@#{GitHub.stealth_email_host_name}\s*\z/i

  # Public: Does the email match the format of Stealth Emails?
  # Returns truthy
  def self.stealthy_email?(email)
    STEALTH_EMAIL_HOST_NAME_REGEX.match?(email)
  end

  def initialize(user)
    @user = user
  end

  # Public: Can the user add and use a stealth_email?
  def valid?
    return false unless GitHub.stealth_email_enabled?
    emails.verified.any? && user.primary_user_email
  end

  def save!
    email_object = user.emails.build(email: email, allow_stealth: true)
    email_object.email_roles.build(role: "stealth", user: user)
    email_object.mark_as_verified
    email_object.save!
  end

  # Public: the email used if a user chooses to keep their
  # email private
  #
  # Returns a String
  def email(username = display_login)
    if @user.is_enterprise_managed?
      @user.profile_email
    else
      "#{user.id}+#{username}@#{GitHub.stealth_email_host_name}"
    end
  end

  # Public: Our old style of stealth email address.
  #
  # Returns a String.
  def legacy_email
    "#{user.display_login}@#{GitHub.stealth_email_host_name}"
  end

  # Public: updates the email after the user has been renamed
  def rename!(new_login)
    email_object = emails.with_role("stealth")
    email_object.update! email: email(new_login), allow_stealth: true
  end

  # Public: Returns a normalized, account-rename safe version of a stealty email.
  def normalized_stealth_email
    return unless StealthEmail.stealthy_email?(email)

    "#{user.id}+username@#{GitHub.stealth_email_host_name}"
  end
end
