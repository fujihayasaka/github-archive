# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateGitHubProximaTenantShortcode < Base
      # Most transitions iterate over a dataset. To do that, use and configure
      # an iterator using `iterate_over`. See the common database table
      # iterator example below, or check the iterators base class
      # (`GitHub::Transitions::Iterators::Base`) to learn how to implement
      # a custom iterator.
      #
      # In case you are not iterating over a dataset but want to perform a
      # one-off action, you can overwrite the `#perform` method.

      sig { override.void }
      def after_initialize
        @tenant = T.let(Business.find_by(slug: arguments[:business_slug]), T.nilable(Business))
      end

      sig { override.void }
      def perform
        log "configuration dry-run=#{dry_run?} parallel=#{parallel?} workers=#{worker_count}"

        unless GitHub.multi_tenant_enterprise?
          log "Not running in multi tenant mode. No action taken."
          return
        end
        if @tenant.blank?
          log "The #{arguments[:business_slug]} tenant does not exist on this stamp. No action taken."
          return
        end

        # set the tenant at the beginning so we always know what context we're working in
        GitHub::CurrentTenant.set(@tenant)

        old_shortcode = arguments[:old_shortcode]
        new_shortcode = arguments[:new_shortcode]

        if old_shortcode == new_shortcode
          log "The provided old_shortcode value \"#{old_shortcode}\" cannot be the same as the new_shortcode value \"#{new_shortcode}\". No action taken."
          return
        end

        # for idempotency - if the shortcode for the business has already been changed in a previous run,
        # ensure that the new_shortcode argument is the same current shortcode on the tenant
        if @tenant.shortcode != old_shortcode && @tenant.shortcode != new_shortcode
          log "The shortcode is already updated to #{@tenant.shortcode} which does not match the provide new_shortcode value: #{new_shortcode}. No action taken."
          return
        end

        # update business shortcode
        if dry_run?
          log "#{arguments[:business_slug]} tenant shortcode would be updated to #{new_shortcode}"
        else
          # only update the shortcode and log if it hasn't already been updated
          if new_shortcode != @tenant.shortcode
            write_to(model_class: Business) do
              @tenant.update_column(:shortcode, new_shortcode)
            end
            log "#{arguments[:business_slug]} tenant shortcode updated to #{new_shortcode}"
          end
        end

        max_length_without_shortcode = User::LOGIN_MAX_LENGTH - new_shortcode.length - 1
        email_regex = /\+#{old_shortcode}@/i
        first_admin_email_regex = /\+#{old_shortcode}-admin@/i

        User.where(business_id: @tenant.id).find_each(batch_size: 250) do |user|
          # skip mannequins since mannequins are having the shortcodes removed altogether
          # see https://github.com/github/github/pull/292337/files#r1364339273
          next if user.mannequin?

          # specifically check the first admin login because is_first_emu_owner? depends on the current shortcode
          if user.login == "#{old_shortcode}_admin"
            first_admin_new_login = "#{new_shortcode}_admin"
            result = update_user_login(user, first_admin_new_login)
            next unless result
            # this is the only piece not idempotent. If the first admin login was already updated
            # but the emails were not, the next run of this transition the first admin would fall into the else branch
            # and the first admin emails would be skipped.
            update_email(user, new_shortcode, first_admin_email_regex, max_length_without_shortcode)
            update_gravatar_email(user, new_shortcode, first_admin_email_regex)
          else
            # for idempotency -
            # First admin: if the first admin has already been updated on a previous run
            # it would fall into this branch and we don't want to update it again.
            next if user.login.ends_with?("_admin")

            # Update login for Users and Organizations.
            # Renaming also updates the repository owner_login field for any repos owned by the user.
            # Check ends_with?("github") to see if it's already been updated. If it has, skip.
            if user.login.ends_with?("_#{old_shortcode}")
              result, new_login = build_user_login(user, old_shortcode, new_shortcode, max_length_without_shortcode)
              next unless result
              result = update_user_login(user, new_login)
              # if updating the login fails, skip the rest of the updates for this user
              next unless result
            end

            # Update emails for Users. Organizations do not have emails.
            if user.user?
              update_email(user, new_shortcode, email_regex, max_length_without_shortcode)
              update_gravatar_email(user, new_shortcode, email_regex)
            end

            if user.public_keys.present?
              update_credential_authorizations(user, new_shortcode)
            end
          end
        end
      ensure
        GitHub::CurrentTenant.reset
      end

      # Build the new user login with the new shortcode appended.
      # If the login is too long for suspended users truncate the login without the shortcode to fit before adding the new shortcode.
      # Returns a bool to indicate if we were able to build the new login, and the new_login if available.
      sig { params(user: User, old_shortcode: String, new_shortcode: String, max_length_without_shortcode: Integer).returns([T::Boolean, T.untyped]) }
      def build_user_login(user, old_shortcode, new_shortcode, max_length_without_shortcode)
        login_without_shortcode = user.login.chomp("_#{old_shortcode}")

        if login_without_shortcode.length > max_length_without_shortcode
          if user.user? && user.suspended?
            # truncate the login_without_shortcode following established patterns for suspended users
            login_without_shortcode = login_without_shortcode[0, max_length_without_shortcode]
          else
            log "#{user.login} login_without_shortcode is too long to be updated to #{login_without_shortcode}_#{new_shortcode}. Skipping."
            return [false, nil]
          end
        end

        new_login = User.standardize_login(login_without_shortcode, suffix: new_shortcode)
        [true, new_login]
      rescue => e
        log "Error building new user login for #{user.login}: #{e}"
        [false, nil]
      end

      # Update the user.login to the new_login.
      # Returns true if the login is updated successfully, otherwise return false.
      sig { params(user: User, new_login: String).returns(T::Boolean) }
      def update_user_login(user, new_login)
        if dry_run?
          log "#{user.login} login would be updated to #{new_login}"
          true
        else
          begin
            prev_login = user.login
            result = T.let(nil, T.untyped)
            write_to(model_class: ApplicationRecord::Domain::KeyValues) do
              write_to(model_class: User) do
                write_to(model_class: BusinessUserAccount) do
                  write_to(model_class: Repository) do
                    result = user.rename!(new_login) unless prev_login == new_login
                  end
                end
              end
            end

            if result == false
              log "#{user.login} rename! to #{new_login} returned false. Skipping."
              return false
            end

            log "#{prev_login} login updated to #{new_login}"
            true
          rescue => e
            log "Error updating #{user.login} login to #{new_login}: #{e}"
            false
          end
        end
      end

      # Update the user's emails. Acheives this by first adding a new email and then removing the old email.
      # If the user is suspended and had their login truncated, we also truncate their obfuscated email.
      sig { params(user: User, new_shortcode: String, regex: T.untyped, max_length_without_shortcode: Integer).void }
      def update_email(user, new_shortcode, regex, max_length_without_shortcode)
        old_email = user.email

        # if the user's existing email includes the new new_shortcode already then we don't need to update the email
        return if old_email.nil? || old_email.include?(new_shortcode)

        # copied from remove_shortcode in packages/external_identities/app/models/user/enterprise_managed_dependency.rb
        email_without_shortcode = user.email.sub(regex, "@")

        if user.suspended?
          # truncate the email if user is suspended to be consistent with user_data_reconciler
          split_email = email_without_shortcode.split("@")
          front = split_email[0][0, max_length_without_shortcode]
          email_without_shortcode = front + "@" + split_email[1]
        end

        # build the new primary email with the new shortcode
        new_email = user.add_emu_shortcode_to_emails(email_without_shortcode)
        primary_user_email = user.emails.build(email: new_email)
        unless primary_user_email.valid?
          log "#{user.login} new primary email #{primary_user_email.email} is invalid. Error: #{primary_user_email.errors.full_messages.to_sentence}"
          return
        end

        primary_user_email.mark_as_verified

        # add the new primary email
        if dry_run?
          log "#{user.login} new primary email #{primary_user_email.email} would be added"
        else
          add_status = T.let(nil, T.untyped)
          write_to(model_class: UserEmail) do
            add_status = user.set_primary_email(primary_user_email)
          end

          if add_status.success?
            log "#{user.login} new primary email #{primary_user_email.email} added"
          else
            log "#{user.login} new primary email #{primary_user_email.email} failed to be added. Error: #{add_status.error}"
            # don't try to remove the old email if the new one wasn't added
            return
          end
        end

        # remove the old primary email
        if dry_run?
          log "#{user.login} old email #{old_email} would be removed"
        else
          remove_status = T.let(nil, T.untyped)
          write_to(model_class: UserEmail) do
            remove_status = user.remove_email(old_email)
          end

          if remove_status == false
            log "#{user.login} old email #{old_email} failed to be removed. Error: #{user.errors.full_messages.to_sentence}"
          else
            log "#{user.login} old email #{old_email} removed"
          end
        end
      rescue => e
        log "Error updating #{user.login} emails: #{e}"
      end

      sig { params(user: User, new_shortcode: String, regex: T.untyped).void }
      def update_gravatar_email(user, new_shortcode, regex)
        if user.gravatar_email.present?
          # if the user's gravatar email includes the new new_shortcode already then we don't need to update the email
          return if user.gravatar_email&.include?(new_shortcode)

          # Suspended users' gravatar emails are not obfuscated,
          # so instead of setting to the primary email just modify the existing email for all users.
          gravatar_email_without_shortcode = user.gravatar_email&.sub(regex, "@")
          new_gravatar_email = user.add_emu_shortcode_to_emails(gravatar_email_without_shortcode)

          if dry_run?
            log "#{user.login} gravatar email would be updated to #{new_gravatar_email}"
          else
            user.gravatar_email = new_gravatar_email
            write_to(model_class: User) do
              user.save!
            end
            log "#{user.login} gravatar email updated to #{new_gravatar_email}"
          end
        end
      rescue => e
        log "Error updating #{user.login} gravatar email: #{e}"
      end

      sig { params(user: User, new_shortcode: String).void }
      def update_credential_authorizations(user, new_shortcode)
        # only update credential authorizations, public keys already get updated in rename!
        credential_auths = Organization::CredentialAuthorization.where(actor_id: user.id, credential_type: "PublicKey")
        credential_auths.each do |credential_auth|
          next unless credential_auth.fingerprint_sha256.present?
          next if credential_auth.fingerprint_sha256.ends_with?("_#{new_shortcode}")

          # fingerprint should be the same as the one on the credential that has already been updated
          new_fingerprint_sha256 = credential_auth.credential.fingerprint_sha256
          if dry_run?
            log "#{user.login} credential auth #{credential_auth.id} would be updated with fingerprint #{new_fingerprint_sha256}"
          else
            write_to(model_class: Organization::CredentialAuthorization) do
              Organization::CredentialAuthorization.update(credential_auth.id, fingerprint_sha256: new_fingerprint_sha256)
            end
            log "#{user.login} credential auth #{credential_auth.id} updated with fingerprint #{new_fingerprint_sha256}"
          end
        end
      rescue => e
        log "Error updating #{user.login} keys: #{e}"
      end

    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  # args = GitHub::Transitions::Arguments.parse(ARGV)
  args = GitHub::Transitions::Arguments.parse(ARGV,
    additional_arguments: %w(business_slug old_shortcode new_shortcode)
  )

  GitHub::Transitions::UpdateGitHubProximaTenantShortcode.new(args).run
end
