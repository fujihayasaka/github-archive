# typed: false
# frozen_string_literal: true

module User::EmailVerificationDependency
  # Internal: Send an email verification request on signup.
  #
  # Returns a Boolean.
  def send_email_verification(invitation_token: nil, repo_invitation_token: nil)
    return false unless GitHub.email_verification_enabled?
    return false unless primary_user_email
    primary_user_email.request_verification(invitation_token: invitation_token, repo_invitation_token: repo_invitation_token)
  end

  # Internal: Send email verification requests reminder if a user visits GitHub and
  # sees a "verification needed" banner
  def send_email_verification_reminder
    return unless show_verification_reminder?
    return unless primary_user_email
    primary_user_email.request_verification_reminder
  end

  def show_verification_reminder?
    return false if joined_too_recently_for_email_verification_reminder?
    should_verify_email?
  end

  def joined_too_recently_for_email_verification_reminder?
    created_at && created_at > 30.minutes.ago
  end

  # Public: Returns Boolean indicating whether this user has no verified emails.
  # Does not take into account whether email verification is enabled (for that,
  # see User#should_verify_email?
  def no_verified_emails?
    !verified_emails?
  end

  # Public: Returns Boolean indicating whether this user has non-bouncing user
  # entered verified emails. Does not take into account whether email
  # verification is enabled (for that, see User#should_verify_email?
  def verified_emails?
    return @has_verified_emails if defined?(@has_verified_emails)
    @has_verified_emails = emails.not_bouncing.user_entered_emails.verified.exists?
  end

  # Public: Returns Boolean indicating whether this user has no verified emails.
  # Always false if email verification is disabled at the app level.
  def should_verify_email?
    defined?(@should_verify_email) or @should_verify_email = begin
      GitHub.email_verification_enabled? && no_verified_emails?
    end
    @should_verify_email
  end

  # Public: Must we require a verified email address for this user?
  def must_verify_email?
    return @must_verify_email if defined?(@must_verify_email)

    @must_verify_email =
      if !GitHub.email_verification_enabled?
        false
      elsif force_mandatory_email_verification?
        true
      else
        should_verify_email? && email_verification_applicable?
      end
  end

  # Public: Is email verification appropriate for this user?
  def email_verification_applicable?
    if !GitHub.email_verification_enabled?
      false
    elsif force_mandatory_email_verification?
      true
    elsif is_enterprise_managed?
      false
    else
      content_creation_requires_email_verification? || anonymizing_proxy_user?
    end
  end

  # Public: Does the mandatory email verification feature apply to this user?
  def content_creation_requires_email_verification?
    GitHub.mandatory_email_verification_enabled? && require_email_verification?
  end

  def disable_mandatory_email_verification(actor:)
    if actor.site_admin? && content_creation_requires_email_verification?
      update(require_email_verification: false)
      auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      GitHub.instrument("staff.disable_mandatory_email_verification", auditing_actor.merge(user: self))
      true
    end
  end

  def enable_mandatory_email_verification
    self.require_email_verification = true
    self
  end

  # Make mandatory email verification apply to this user. If the user is not
  # verified (or becomes unverified), content creation will be blocked until
  # the requirement is met.
  def require_email_verification!
    return unless GitHub.mandatory_email_verification_enabled?
    return if require_email_verification?
    enable_mandatory_email_verification.save!
  end

  def restore_mandatory_email_verification(actor:)
    if actor.site_admin?
      require_email_verification!
      auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      GitHub.instrument("staff.restore_mandatory_email_verification", auditing_actor.merge(user: self))
    end
  end

  # Public: Check if user has been marked as exempt from mandatory email
  # verification.
  def exempt_from_mandatory_email_verification?
    !require_email_verification?
  end

  # Public: Check if user needs to verify address before invite members to org by email
  def requires_verification_to_invite_by_email?
    ContentAuthorizer.authorize(self, :organization_invitation, :create).has_email_verification_error?
  end

  # Public: Check if a user can add additional verified emails when they only have one verified email and it was not recently verified
  def add_additional_verified_emails_after_first_verified_email?
    return false unless self.change_email_enabled?
    verified_emails = emails.verified
    return false unless verified_emails.count == 1
    return false if verified_emails.count == 1 && self.is_first_emu_owner?

    verified_emails.first.verified_at.present? && verified_emails.first.verified_at < 1.month.ago
  end

  private

  # Private: Provides a mechanism for forcing mandatory email verification
  # regardless of enrollment in an experiment or a feature flag being
  # configured.
  #
  # Returns true if any of the unverified email addresses associated with the
  # user ends in +forceverify@github.com.
  #
  # Returns a Boolean
  def force_mandatory_email_verification?
    @unverified_emails ||= emails.unverified.to_a
    @unverified_emails.any? { |email| email.email =~ /\+forceverify@github\.com\Z/ }
  end
end
