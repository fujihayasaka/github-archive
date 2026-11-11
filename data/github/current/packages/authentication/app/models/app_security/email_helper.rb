# typed: true
# frozen_string_literal: true

module AppSecurity
  module EmailHelper
    include Kernel
    extend self

    # user: User object to unlink email from
    # email: Email object to unlink from user's account
    #
    # Returns a boolean indicating success
    def unlink_from_account(user, email, actor: user, two_factor_lockout: false)
      if email.nil? || email.user_id != user.id
        return "Email is not associated with this account"
      end

      preventative_message = prevent_email_unlink_message_base(email)
      return preventative_message if preventative_message.present?

      # capture the state of the email within the account at the start
      remove_email_options = { actor: actor }

      email_roles = email.email_roles.map { |email_role| email_role.role }.uniq
      remove_email_options[:email_roles] = email_roles - %w[stealth suppressed]

      if two_factor_lockout
        remove_email_options[:account_lockout] = true
        remove_email_options[:account_recovery_audit_metadata] = {
          account_recovery_unlinked: true,
          account_recovery_valid: email.verified? && !email.bouncing? && (
            email.primary_role? || user.account_related_emails.include?(email))
        }
      end

      error = T.cast(nil, T.untyped)
      should_disable_notifications = T.cast(false, T.nilable(T::Boolean))

      User.transaction do
        begin
          if email.primary_role?
            replacement = self.fallback_for_primary_email(user)
            unless replacement
              if GitHub.enterprise?
                error = "Cannot remove this email from this account, please add another before deleting '#{email.email}'"
                raise ActiveRecord::Rollback
              end

              unlink_suffix = Time.now.utc.strftime("%Y%m%d%H%M") # e.g. 202301311003 for Jan 31, 2023 at 10:03 UTC
              replacement = user.add_email("#{email.email}.unlinked#{unlink_suffix}", actor: user)

              should_disable_notifications = true
            end

            set_primary_email_status = user.set_primary_email(replacement)
            if set_primary_email_status.error?
              error = set_primary_email_status.error
              raise ActiveRecord::Rollback
            end
          end

          unless user.remove_email(email, **remove_email_options)
            error = user.errors.full_messages.to_sentence
            raise ActiveRecord::Rollback
          end
        rescue ActiveRecord::ActiveRecordError => e
          if e.is_a?(ActiveRecord::Rollback)
            raise e
          end

          error = "Something went wrong while unlinking the email from the account"
          Failbot.report(e)
          raise ActiveRecord::Rollback
        end
      end

      if error.nil? && should_disable_notifications
        # Disable notifications for the user since then account will essentially be abandoned
        user.disable_all_notifications
      end

      error
    end

    # prevent emails linkes to Sponsors profiles from being unlinked
    def prevent_email_unlink_message(email_string)
      prevent_email_unlink_message_base(UserEmail.find_by(email: email_string))
    end

    private

    def prevent_email_unlink_message_base(email)
      if email.sponsors_listing
        return "This email is being used as your contact email for GitHub Sponsors and cannot be unlinked. Please change the email in your GitHub Sponsors settings or application and try again."
      end

      nil
    end

    def fallback_for_primary_email(user)
      # We let the caller handle the case where this is the user's last email,
      # since several things need to happen (register a placeholder email, disable
      # notifications, etc).
      return nil if user.primary_user_email.last_email?
      # When a user has chosen to allow password resets only with their primary
      # email, we set their backup email to match their primary email. So, we
      # don't want to return their "backup email", since it is the same as the
      # user's primary email.
      if user.has_backup_email? && !user.password_reset_with_primary_email_only?
        return user.backup_user_email
      end
      # If the user doesn't have a backup set, then we search for the next
      # available "notifiable email". Notifiable emails prefer verified emails.
      # However, if no verified emails exist (notice we exclude the user's
      # primary/backup email before doing the search), then it falls over to the
      # first available unverified email.
      user.emails.excluding_ids([user.primary_user_email, user.backup_user_email]).notifiable.first
    end
  end
end
