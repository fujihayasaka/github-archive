# typed: true
# frozen_string_literal: true

module Settings
  class EmailsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :user

    def bouncing_tooltip(email)
      "The mailserver for #{email.domain} is not accepting our messages to #{email.email}"
    end

    # Public: Is deletion disabled for this email?
    # Returns a Boolean.
    def deletion_disabled?(email, email_social_info: nil)
      email.last_email? ||
      primary_without_notifiable_alternate?(email) ||
      primary_with_only_backup_alternate?(email) ||
      social_disconnect_disabled?(email, email_social_info: email_social_info)
    end

    # Public: The deletion message for an email?
    # Returns a Boolean.
    def deletion_message(email)
      delete_message = "Are you sure you want to remove this email from your account? Once removed, commits attributed to this email address will no longer be associated with your account."
      if email.primary_role?
        delete_message += " One of your other emails will become your primary address."
      elsif email.backup_role?
        delete_message += " Removing your backup email will allow #{password_reset_email_type_fragment} to be used for password resets."
      end
      delete_message
    end

    # Public: Returns a String tooltip based on deletion
    # rules for the email.
    def deletion_tooltip(email, email_social_info: nil)
      if email.last_email?
        "At least one email is required."
      elsif primary_without_notifiable_alternate?(email)
        email_type = if GitHub.email_verification_enabled? && user.verified_emails?
          "verified email"
        else
          "useable email"
        end
        "At least one #{email_type} is required."
      elsif primary_with_only_backup_alternate?(email)
        "At least one non-backup email is required."
      elsif social_disconnect_disabled?(email, email_social_info: email_social_info)
        "You must set a password first."
      else
        "Delete #{email}"
      end
    end

    def social_disconnect_disabled?(email, email_social_info: nil)
      user.is_passwordless_user? && email_social_info && email_social_info[:email_id] == email.id
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def primary_email_address
      @primary_email_address ||= primary_email_role&.email&.email
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def primary_email_address_is_public?
      primary_email_role&.public?
    end

    def has_emails?
      user.emails.any?
    end

    # Public: Returns a string of the current in use stealth email
    # or the email that will be generated
    def stealth_email_display
      if primary_email_address_is_public?
        StealthEmail.new(user).email
      else
        stealth_email = user.emails.find { |e| e.role?("stealth") }
        (stealth_email || StealthEmail.new(user)).email
      end
    end

    def verification_enabled?
      GitHub.email_verification_enabled?
    end

    # Internal: Is the email the primary email address for the user
    # and no other verified email addresses exist?
    #
    # Returns a Boolean.
    def primary_without_notifiable_alternate?(email)
      email.primary? &&
      user.emails.notifiable.excluding_ids(email).none?
    end

    # Internal: Is the email the primary email address for the user and no
    # other email addresses exist that could become the user's new default
    # primary if the primary is deleted.
    #
    # Returns a Boolean.
    def primary_with_only_backup_alternate?(email)
      email.primary? &&
      user.emails.notifiable.excluding_ids([email, user.backup_user_email]).none?
    end

    # Internal: Creates an array of select options for choosing a primary email
    # address. This list includes all of a users notifiable addresses, minus
    # their backup email address if one is configured (because an email can
    # either be a primary or backup, but not both).
    #
    # Returns an array of select values.
    def primary_email_select_options
      emails = user.emails.notifiable.map { |email| [email.to_s, email.id] }

      # When a user has chosen to only allow their primary email address to be
      # used for password resets we model that by setting their backup email
      # address equal to their primary email address behind the scenes. So, we
      # don't want to delete anything in this case, since their primary == the
      # backup email.
      if !user.password_reset_with_primary_email_only? && user.has_backup_email?
        emails.delete([user.backup_user_email.to_s, user.backup_user_email.id])
      end
      emails
    end

    # Internal: Creates an array of select options for choosing a backup email
    # address. This list includes all of a users verified addresses, minus
    # their primary email address (because an email can either be a primary or
    # backup, but not both). This list also includes an "all" option, which is
    # the default value when no explicit backup email has been selected by a
    # user.
    #
    # Returns an array of select values.
    def backup_email_select_options
      emails = [
        ["Allow #{password_reset_email_type_fragment}", UserEmailsController::BACKUP_EMAIL_ALLOW_ALL],
        ["Only allow primary email", UserEmailsController::BACKUP_EMAIL_PRIMARY_ONLY],
      ]
      emails + emails_for_backup.map { |email| [email.to_s, email.id] }
    end

    def hide_backup_email_options
      user.scim_managed_user?
    end

    # Internal: Determines the id of the user's currently configured backup
    # email.
    #
    # Returns an integer id or nil
    def backup_email_default_selection
      if user.password_reset_with_primary_email_only?
        UserEmailsController::BACKUP_EMAIL_PRIMARY_ONLY
      elsif user.has_backup_email?
        user.backup_user_email.id
      else
        UserEmailsController::BACKUP_EMAIL_ALLOW_ALL
      end
    end

    # Internal: Determines the id of the user's curretly configured primary
    # email.
    #
    # Returns an integer id or nil
    def primary_email_default_selection
      user.primary_user_email.id if user.has_primary_email?
    end

    # Internal: Creates an array of emails that are elligible to use as a
    # user's backup email. The emails must be verified and can't already be
    # their primary email.
    #
    # Returns an an array of emails or an empty array if no emails are
    # elligible to be used as a backup email.
    def emails_for_backup
      emails = []
      # We don't want to allow any emails that are unverified unless email
      # verification is disabled.
      if !GitHub.email_verification_enabled? || user.verified_emails?
        emails = user.emails.notifiable.to_a
        emails.delete(user.primary_user_email)
      end
      emails
    end

    # Internal: Determines the type of emails that can be used for password resets.
    #
    # Returns a String fragment with the kind of emails that can be used for
    # password resets.
    def password_reset_email_type_fragment
      if !GitHub.email_verification_enabled?
        "all emails"
      elsif user.verified_emails?
        "all verified emails"
      else
        "all unverified emails"
      end
    end

    def settings_available?
      settings_response.success?
    end

    def global_notifications_email
      if settings_available?
        settings.email(:global).address
      end
    end

    def is_global_notifications_email?(email)
      global_notifications_email == email.to_s
    end

    private

    def primary_email_role
      @primary_email_role ||= user.primary_user_email_role
    end

    def settings_response
      @settings_response ||= GitHub.newsies.settings(user)
    end

    def settings
      @settings ||= settings_response.value
    end
  end
end
