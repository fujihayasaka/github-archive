# typed: true
# frozen_string_literal: true

class EmailUnlink
  TOKEN_SCOPE = "EmailUnlink"
  EXPIRY      = 3.hours

  def initialize(user, email: nil, expires: EXPIRY.from_now, emails_sent: false, success: nil, staff_initiated: false, flash_messages: {})
    @user = user
    @requested_email = email
    @expires = expires
    @emails_sent = emails_sent
    @success = success
    @staff_initiated = staff_initiated
    @flash_messages = flash_messages
  end

  # Public: A SignedAuthToken to send in the email to the user.
  #
  # Returns a SignedAuthToken or nil if the EmailUnlink is invalid.
  def token
    user.signed_auth_token(
      scope: TOKEN_SCOPE,
      expires: @expires,
      data: {
        email: email,
        emails_sent: @emails_sent,
        success: @success,
        staff_initiated: @staff_initiated,
        flash_messages: @flash_messages,
      },
    )
  end

  # Public: a EmailUnlink model deserialized from a SignedAuthToken
  #
  # Returns an EmailUnlink or nil.
  def self.build_from_token(string_token)
    token = verify_signed_auth_token(string_token)
    return unless token.valid?

    new(
      token.user,
      expires: token.expires,
      email: token.data["email"],
      emails_sent: token.data["emails_sent"],
      success: token.data["success"],
      staff_initiated: token.data["staff_initiated"],
      flash_messages: token.data["flash_messages"]&.symbolize_keys || {},
    )
  end

  # Public: the email link the user needs to follow to unlink their email.
  #
  # Returns a String
  def link
    "#{GitHub.url}/sessions/email_unlink/#{token}"
  end

  def user
    @user
  end

  # Public: The email address this EmailUnlink will be sent to
  #
  # Returns a String email address or nil.
  def email
    @requested_email
  end

  def is_expired
    @expires < Time.now
  end

  def emails_sent?
    @emails_sent
  end

  def mark_emails_sent!
    @emails_sent = true
  end

  def staff_initated?
    @staff_initiated == true
  end

  def successful?
    @success == true
  end

  def failed?
    @success == false
  end

  def complete!
    @success = true
  end

  def fail!
    @success = false
  end

  [:notice, :warn, :error].each do |type|
    define_method "flash_#{type}?" do
      @flash_messages[type].present?
    end

    define_method "flash_#{type}" do
      @flash_messages[type]
    end

    define_method "flash_#{type}=" do |value|
      @flash_messages[type] = value
    end
  end

  def self.verify_signed_auth_token(token)
    User.verify_signed_auth_token(
      token: token,
      scope: TOKEN_SCOPE,
    )
  end
  private_class_method :verify_signed_auth_token

end
