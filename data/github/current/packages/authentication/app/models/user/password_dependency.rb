# typed: true
# frozen_string_literal: true

module User::PasswordDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { User }

  WEAK_PASSWORD_MESSAGE = "is in a list of passwords commonly used on other websites"
  TOO_SHORT_MESSAGE = "is too short (minimum is #{GitHub.password_minimum_length} #{"character".pluralize(GitHub.password_minimum_length)})"
  TOO_LONG_MESSAGE = "is too long (maximum is #{GitHub.password_maximum_length} #{"character".pluralize(GitHub.password_maximum_length)})"
  LOWERCASE_NEEDED_MESSAGE = "needs at least #{GitHub.password_lowercase_requirement} lowercase #{"letter".pluralize(GitHub.password_lowercase_requirement)}"
  NUMBER_NEEDED_MESSAGE = "needs at least #{GitHub.password_digit_requirement} #{"number".pluralize(GitHub.password_digit_requirement)}"
  TIME_ALLOWED_BEFORE_BLOCK = 30.days

  class_methods do
    # Authenticates a User by their login name and unencrypted password, or
    # an OAuth access token and no password or 'x-oauth-basic'
    #
    # Returns the User or nil.
    def authenticate(login, password)
      return unless u = User.find_by_login_or_email(login)

      success, message = u.authenticated_by_password?(password)
      [success ? u : nil, message]
    end
  end

  # Public: Sets a new password for the user verifying the old password.
  #
  # old_password - String password.
  # password - String password.
  # password_confirmation - String password.
  def change_password(old_password:, password:, password_confirmation:, from_device_id: nil)
    return false if is_emu_and_not_first_owner?

    # if we have hit a limit due to too many password change attempts with an incorrect old password, stop here
    if AuthenticationLimit.at_any?(change_password_login: login, increment: false)
      errors.add(:base, "Too many failed password change attempts due to an incorrect old password. Try again later.")
      return false
    end

    unless (self.password_hash.nil? && old_password.nil?) || password_match?(old_password)
      # increment the authentication limit if the old password is wrong
      AuthenticationLimit.at_any?(change_password_login: login, increment: true)

      errors.add(:old_password, "isn't valid")
      return false
    end

    if update(old_password: old_password, password: password, password_confirmation: password_confirmation)
      self.update_weak_password_check_result
      clear_auth_limit
      clear_dependencies(:password_changed, from_device_id: from_device_id)

      instrument :change_password
      GlobalInstrumenter.instrument(
        "user.password_update",
        actor: self,
        account: self,
        update_type: :USER_CHANGE,
      )
      AccountMailer.password_changed(self, "changed").deliver_later
    end
  end

  # Public: Initiates a password reset for a user.
  #
  # password - String password.
  # password_confirmation - String password.
  #
  # Returns true if password is updated, false otherwise.
  def apply_password_reset(password:, password_confirmation:, from_device_id: nil, parsed_useragent: nil, tfa: false, tfa_method: nil)
    return false if is_emu_and_not_first_owner?

    # because regular validation allows blank password (silently ignores it)
    if password.blank?
      errors.add(:password, "can't be blank")
      return false
    end

    # TODO: remove once password_not_weak doesn't need it
    @password_changed_reason = "reset"
    if update(password: password, password_confirmation: password_confirmation)
      self.update_weak_password_check_result
      clear_auth_limit
      clear_dependencies(:password_reset, from_device_id: from_device_id, parsed_useragent: parsed_useragent)

      payload = { actor: self, two_factor_required: tfa }
      payload[:two_factor_method] = tfa_method if tfa
      instrument :reset_password, payload
      GlobalInstrumenter.instrument(
        "user.password_update",
        actor: self,
        account: self,
        update_type: :USER_RESET,
      )
      AccountMailer.password_changed(self, "reset").deliver_later
      return true
    end

    false
  end

  # Called after password resets, password changes, and password randomizations.
  private def clear_dependencies(reason, revoke_oauth_accesses: false, from_device_id: nil, parsed_useragent: nil)
    if GitHub::Authentication::KV.store.get(RevokeCompromisedSessionJob.pending_revocation_key(self.id)).value { nil } == "true"
      GitHub.dogstats.increment("user_session.risk_revocation.pending.account_action", tags: ["reason:#{reason}", "action:password_change"])
    end
    revoke_active_sessions(reason)
    unverify_all_devices_but_current(reason, from_device_id: from_device_id, parsed_useragent: parsed_useragent) if sign_in_analysis_enabled?
    revoke_oauth_accesses(reason) if revoke_oauth_accesses
  end

  private def unverify_all_devices_but_current(reason, from_device_id:, parsed_useragent:)
    current_device = if from_device_id
      display_name = AuthenticatedDevice.generated_display_name(parsed_useragent)
      AuthenticatedDevice.find_device_or_create!(self, device_id: from_device_id, display_name: display_name).tap do |_, device|
        device.verify!
      end
    end

    count = authenticated_devices.verified.where.not(id: current_device).update_all(approved_at: nil)
    GitHub.dogstats.count("authenticated_device", count, tags: ["action:unverify", "reason:#{reason}"])
  end

  private def revoke_oauth_accesses(reason)
    ::RevokeOauthAccessesJob.perform_later(self, explanation: reason, enqueued_at: Time.zone.now)
  end

  # Public: scramble the user's password. Used by support during recovery of a hijacked account.
  def set_random_password(actor:, send_notification: true)
    random_password = SecureRandom.hex(32)

    if update(password: random_password, password_confirmation: random_password)
      self.update_weak_password_check_result
      clear_dependencies(:password_randomized, revoke_oauth_accesses: true)

      instrument :randomize_password, GitHub.guarded_audit_log_staff_actor_entry(actor)
      GlobalInstrumenter.instrument(
        "user.password_update",
        actor: actor,
        account: self,
        update_type: :SET_RANDOM,
      )
      AccountMailer.password_changed(self, "changed").deliver_later if send_notification
      true
    end
  end

  # Public: Given a user and a requested email address, look for a match on the user's stored password reset emails and return it.
  #
  # Returns the stored data instead of using the input data so that case is preserved, since the local part of emails can technically be case-sensitive.
  #
  # Uses `password_reset_emails` to determine which emails are allowed.
  #
  # Returns String or nil
  def lookup_password_reset_email(requested_email_address)
    password_reset_emails.map(&:to_s).find { |email| ascii_upcase(email) == ascii_upcase(requested_email_address) }
  end

  def ascii_upcase(str)
    str.upcase(:ascii)
  end

  # Public: Is the specified email address acceptable for us to use to contact
  # them for password resets?
  #
  # If email verification is disabled (on Enterprise), we can use either
  # unverified or verified emails. Yes, emails shouldn't be verified if email
  # verification is disabled, but there have been bugs in the past that have
  # allowed this to happen.
  #
  # Otherwise, the following are allowed:
  #   * Primary email
  #   * Backup email (if set)
  #   * Any "notifiable" email - This includes all verified emails.
  #     If no emails are verified it includes all user entered emails.
  #
  # Returns Boolean
  def is_password_reset_email?(email_address)
    lookup_password_reset_email(email_address).present?
  end

  # Public: return the list of UserEmail that can be used for password reset.
  # This method doubles as the list of email addresses where important account
  # security emails are to be delivered. All email addresses returned should
  # pass the `is_password_reset_email?` check
  #
  # Returns:
  #   * Primary email if password_reset_with_primary_email_only is set
  #   * Primary email and Backup email (if set)
  #   * Primary email and any "notifiable" email
  #      * This includes all verified emails.
  #      * If no emails are verified it includes all user entered emails.
  def password_reset_emails
    # in multi-tenant mode, we need to use "outbound_email"
    # so that the password reset isn't reliant on the "internal email"
    # we store on the first emu admin
    primary = GitHub.multi_tenant_enterprise? ? outbound_email : primary_user_email
    if password_reset_with_primary_email_only?
      [primary]
    elsif has_backup_email?
      [primary, backup_user_email]
    else
      # The primary email is always valid for password reset, verified or not
      Set.new(T.let(emails, T.untyped).notifiable + [primary])
    end
  end
  alias account_related_emails password_reset_emails

  def forgot_password(password_reset)
    hours_until_expiry = ((password_reset.expires - Time.now) / 1.hour).round
    CriticalAccountLoginMailer.new_password(
      password_reset.user,
      password_reset.email,
      password_reset.link,
      hours_until_expiry,
      password_reset.forced_weak_password_reset?,
      password_reset.new_reset_link,
    ).deliver_later
    instrument :forgot_password, email: password_reset.email, forced_reset: password_reset.forced_weak_password_reset?
  end

  def instrument_two_factor_recovery_without_password
    instrument :initiate_two_factor_recovery_without_password
  end

  # Internal: Determines if password validation (minimum length, special chars, etc.) should be performed before saving the user.
  # Password validation applies for all users who have passwords. The cases when users don't have passwords are:
  #  - social sign-up users. registered to GitHub through an external OAuth provider
  #
  # Returns true or false.
  def password_validation_required?
    !password.nil? || (password_hash.blank? && !FeatureFlag.vexi.enabled?(:user_allow_nil_password, self, default: false))
  end

  # Internal: Hash the password and set password_hash.
  def hash_password
    if !password.blank? && @password
      self.password_hash = GitHub::Password.create(password)
      if GitHub.keep_legacy_bcrypt_password?
        self.bcrypt_auth_token = BCrypt::Password.create(password, cost: GitHub.bcrypt_password_cost)
      end
      @password = nil
    end
  end

  # Public: returns true if a new password will be saved
  def will_save_change_to_password?
    will_save_change_to_password_hash?
  end

  # Internal: returns true if a new password has been saved
  def saved_change_to_password?
    saved_change_to_password_hash?
  end

  # Calculates the Shannon entropy value.
  # Source: https://rosettacode.org/wiki/Entropy#Ruby
  def character_variety_heuristic(password)
    counts = Hash.new(0.0)
    password.each_char { |c| counts[c] += 1 }
    leng = password.length

    counts.values.reduce(0) do |entropy, count|
      freq = count / leng
      entropy - freq * Math.log2(freq)
    end
  end

  # Internal: We (loosely) follow some of the password guidelines recommended in
  # the PCI Compliance docs. Namely: at least one downcase letter and
  # one number. If the user is using a passphrase (16+ chars and 2+ spaces),
  # we don't make them conform to those rules.
  #
  # Returns nothing.
  def enforce_stronger_password
    return if password.blank?

    if password.length < User::PASSPHRASE_LENGTH
      if password.length < GitHub.password_minimum_length
        errors.add(:password, TOO_SHORT_MESSAGE)
      end

      if password !~ /[a-z]{#{GitHub.password_lowercase_requirement},}/
        errors.add(:password, LOWERCASE_NEEDED_MESSAGE)
      end

      if password !~ /[A-Z]{#{GitHub.password_uppercase_requirement},}/
        errors.add(:password, "needs at least #{GitHub.password_uppercase_requirement} uppercase #{"letter".pluralize(GitHub.password_uppercase_requirement)}")
      end

      if password !~ /[0-9]{#{GitHub.password_digit_requirement},}/
        errors.add(:password, NUMBER_NEEDED_MESSAGE)
      end

      if password !~ /\W{#{GitHub.password_special_character_requirement},}/
        errors.add(:password, "needs at least #{GitHub.password_special_character_requirement} #{"special character".pluralize(GitHub.password_special_character_requirement)}")
      end
    end

    if login.present? && password.downcase.gsub(login.downcase, "").length <= 3
      errors.add(:password, "cannot include your login")
    end
  end

  def password_not_too_long
    return if password.blank?

    if password.length > GitHub.password_maximum_length
      errors.add(:password, TOO_LONG_MESSAGE)
    end
  end

  def provided_weak_password?
    return unless password
    self.validate # if the object has already been validated this won't re-run checks
    errors[:password].include?(WEAK_PASSWORD_MESSAGE)
  end

  def password_related_error?
    return true if errors[:old_password].present?
    return true if errors[:password].present?
    return true if errors[:password_confirmation].present?

    false
  end

  def password_not_weak
    return if password.blank?
    tag = if new_record?
      :create_user
    elsif @password_changed_reason == "reset"
      :password_reset
    else
      :password_change
    end
    if CompromisedPassword.find_using_password(password, user: self, action: tag)
      errors.add(:password, WEAK_PASSWORD_MESSAGE)
    end
  end

  def authenticated_by_password?(password)
    return false if password_hash.nil?

    stored_password = GitHub::Password.from_hash(password_hash)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = stored_password.verify(password)
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    GitHub.dogstats.distribution("password_auth.time", ((finish - start) * 1000).round)

    return false unless result.success

    if result.needs_upgrade?
      write_password_hash(password)
    end
    true
  end

  def password_match?(password)
    return false if password_hash.nil?
    GitHub::Password.from_hash(password_hash).verify(password).success
  end

  def write_password_hash(password)
    ActiveRecord::Base.connected_to(role: :writing) do
      update_column(:password_hash, GitHub::Password.create(password))
    end
  end

  def password_check_metadata
    # we handled the case in encrypted_attribute that if read fails, nil will be returned
    # and we fail open
    if self.weak_password_check_result.present?
      PasswordCheckMetadata.new.read(self.weak_password_check_result)
    else
      PasswordCheckMetadata.new
    end
  end

  def block_deadline
    deadline = if !password_check_metadata.weak?
      TIME_ALLOWED_BEFORE_BLOCK.after(Time.zone.now)
    else
      TIME_ALLOWED_BEFORE_BLOCK.after(Time.zone.at(password_check_metadata.discovery_timestamp))
    end

    deadline.strftime("%B %-d, %Y")
  end

  def update_weak_password_check_result(compromised_password: nil)
    check = PasswordCheckMetadata.new
    if compromised_password
      if !password_check_metadata.weak?
        T.let(check, T.untyped).discovery_timestamp = Time.now.to_i
        T.let(check, T.untyped).compromised_password_id = compromised_password.id
        # if check result was false before and now true, we store the timestamp
        update_attribute(:weak_password_check_result, check.to_binary_s)
      else
        # if check result was true before, and now still true, we reencrypt for
        # security reasons so that it will be indistinguishable from when we update
        # the field when the check returns a none compromised password.
        update_attribute(:weak_password_check_result, self.weak_password_check_result)
      end
    else
      # if check result is false now, we update it to 0
      T.let(check, T.untyped).discovery_timestamp = 0
      T.let(check, T.untyped).exact_email_and_password_match = 0
      update_attribute(:weak_password_check_result, check.to_binary_s)
    end
  end

  def mark_compromised_via_direct_match(password:, name:, version:)
    compromised_password = nil

    compromised_password = CompromisedPassword.find_using_password(
      password,
      user: self,
      stat: false
    )

    tags = [
      "employee:#{self.employee?}",
      "spammy:#{self.spammy?}",
      "tfa_enabled:#{self.two_factor_authentication_enabled?}",
      "version:#{version}",
      "datasource:#{name}",
    ]

    # Very rarely the password is nil after a lookup due to replication
    # lag, we got the OK to read from master in this case
    if compromised_password.nil?
      CompromisedPassword.find_using_password(
        password,
        user: self,
        role: :writing,
        stat: false
      )
      GitHub.dogstats.increment("auth.compromised_password.read_from_primary", tags: tags)
    end

    id = if compromised_password.nil?
      GitHub.dogstats.increment("auth.compromised_password.nil_compromised_password", tags: tags)
      0
    else
      compromised_password.id
    end

    check = PasswordCheckMetadata.new(
      compromised_password_id: id,
      discovery_timestamp: Time.now.to_i,
      exact_email_and_password_match: 1,
    )
    update_attribute(:weak_password_check_result, check.to_binary_s)
    instrument :exact_email_and_password_match, compromised_password: compromised_password, datasource_name: name, datasource_version: version
  end

  def mark_compromised_via_secret_scanning
    tags = [
      "employee:#{self.employee?}",
      "spammy:#{self.spammy?}",
      "tfa_enabled:#{self.two_factor_authentication_enabled?}",
    ]

    check = PasswordCheckMetadata.new(
      compromised_password_id: 0,
      discovery_timestamp: Time.now.to_i,
      exact_email_and_password_match: 1,
    )
    update_attribute(:weak_password_check_result, check.to_binary_s)
    GitHub.dogstats.increment("auth.compromised_password.secret_scanning", tags: tags)

    instrument :exact_email_and_password_match, datasource_name: "secret_scanning"
  end
end
