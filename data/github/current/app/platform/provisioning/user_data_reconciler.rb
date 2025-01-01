# typed: false
# frozen_string_literal: true

# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Provisioning
    class UserDataReconciler
      include Platform::Provisioning::OperationType

      # Standard error messages
      LOGIN_CONFLICT = "Another user already owns the account. Please have your administrator check the authentication log."
      MISSING_LOGIN = "The response did not contain either a valid NameID or a valid configured Username attribute."
      EMAIL_TAKEN = "Another user already owns the email. Please have your administrator check the authentication log."
      EMAILS_EMPTY = "External authentication provided an empty email attribute. Please have your administrator check the authentication log."
      SUSPENDED_USER = "Cannot rename a suspended user through SCIM or SAML endpoints."

      ENTERPRISE_OWNER_ROLE = %w[981df190-8801-4618-a08a-d91f6206c954 36b03fcb-b8aa-40a7-b1c9-ce6a874b699f enterprise_owner]

      RECONCILER_METHODS = [:user_name, :admin, :display_name, :emails, :ssh_keys, :gpg_keys]

      attr_reader :user, :user_data

      # Result of a reconciliation.  Can contain a list of errors.  First fatal error will stop processing
      class Result
        attr_reader :user

        def initialize(user:, errors:)
          @user = user
          @errors = errors
        end

        # Public: Was the result of reconciliation successful?
        #
        # Returns true or false
        def success?
          errors.empty?
        end

        # Public: Check if any of the errors were designated as fatal by the reconciler
        #
        # Returns true or false
        def has_fatal?
          errors.any? { |_k, v| v.fatal? }
        end

        # Public: Attribute reader for errors
        #
        # Returns errors when the value for error is not nil
        def errors
          @errors.reject { |_k, v| v.nil? }
        end

        # Public: Error message reader for a given reconciler
        #
        # Returns error message for a given reconciler
        def error_message(message_for)
          @errors[message_for].message unless @errors[message_for].nil?
        end

        # Public: Convert a hash of errors to an array of errors
        #
        # Returns an array of errors
        def error_values
          errors.values
        end
      end

      # Public: Create a UserDataReconciler class by passing user and a user data
      #
      # user - current user that the data is being reconciled for
      # user_data - data to reconcile (SCIM or SAML)
      # reason - error reason, where the reconciler was called from, create or update.  Used
      #          in creating errors for email messages
      # flags - flags passed into a reconciler, only pass in flags to change the default
      #     is_enterprise_server: true - is the reconciler called from enterprise server (GHES)
      #     is_emu: false - is the reconciler called from a enterprise managed identity provisioner
      #     reconcile_methods: methods to reconcile, default is all methods
      # error_options - options for the reconciler, to override fatal/non-fatal errors
      def initialize(
        user,
        user_data,
        reason:,
        flags: {},
        error_options: {}
      )
        @user = user
        @user_data = user_data
        @reason = reason

        @error_options = {
          missing_login: true,
          login_conflict: true,
          remove_old_emails: false,
          primary_email_blank: false,
          email_taken: true,
          primary_email_error: true,
          suspended_user: true,
        }

        @flags = {
          is_enterprise_server: true,
          is_emu: false,
          reconcile_methods: RECONCILER_METHODS,
          clear_profile: false,
          skip_reserved_domain: false,
        }

        set_options(error_options)
        set_flags(flags)
      end

      # Public: Return a user name that is going to be used in name reconciliation
      #
      # Returns String
      def self.user_name(user_data, suffix: nil)
        # Azure will attempt to rename a user when the user is being SUSPENDED through SCIM
        # The user name will be in the following format: external_id + old UPN
        # Since there is a limit of User::LOGIN_MAX_LENGTH characters for a user_name it will most likely
        # fail that validation check.  In order to make that user_name unique, we
        # are going to set it to the external_id instead of a user_name
        if user_data.active?
          user_data.user_name
        else
          obfuscate_value(user_data.user_name, user_data.external_id, suffix)
        end
      end

      def self.email(user_data, email, suffix: nil)
        # removing a user from an application has a different meaning for different IdPs.
        # Azure, will send a active = false when the user is removed from an application or
        # deleted from a tenant.  Since Azure has a notion of a soft delete (user can be restored),
        # Azure will send a DELETE when the user is actually removed from a tenant.  The attributed
        # received in the SCIM PATCH differ based on where the deleted has occurred in Azure.
        # Delete from an application will only send the active = false attribute, soft delete from a
        # tenant will send the updated userName and primary email as well.  In order to make the suspension
        # PATCH seamless, we will modify the primary email of a user.
        if user_data.active?
          email
        else
          split_email = email.split("@")
          split_email[0] = obfuscate_value(split_email[0], user_data.external_id, suffix)
          split_email.join("@")
        end
      end

      # Public: a method to obfuscate a value with a suffix
      #
      # external_id - deprecated and no longer used.
      #
      # Returns String
      def self.obfuscate_value(value, external_id, suffix)
        suffix_length = suffix ? suffix.length + 1 : 0
        guid = SimpleUUID::UUID.new.to_guid
        # make sure the the login does not exceed the required User::LOGIN_MAX_LENGTH characters
        Digest::SHA256.hexdigest(value + guid)[0, User::LOGIN_MAX_LENGTH - suffix_length]
      end

      # Public: A class reconcile method for user and a user data
      #
      # user - current user that the data is being reconciled for
      # user_data - data to reconcile (SCIM or SAML)
      # reason - error reason, where the reconciler was called from, create or update.  Used
      #          in creating errors for email messages
      # flags - flags passed into a reconciler, only pass in flags to change the default
      #     is_enterprise_server: true - is the reconciler called from enterprise server (GHES)
      #     is_emu: false - is the reconciler called from a enterprise managed identity provisioner
      #     reconcile_methods: methods to reconcile, default is all methods
      # error_options - options for the reconciler, to override fatal/non-fatal errors
      #
      # Returns Result of reconciliation
      def self.reconcile(
        user,
        user_data,
        reason: PROVISION,
        flags: {},
        error_options: {}
      )
        raise ArgumentError, "expected user to be not blank" if user.nil?
        raise ArgumentError, "expected user_data to be not blank" if user_data.nil?

        new(
          user,
          user_data,
          reason: reason,
          flags: flags,
          error_options: error_options
        ).reconcile
      end

      # Internal: A reconcile method, reconciles each value.
      #           First fatal error will stop further reconciliation.
      #
      # Returns a Result of a reconciliation
      def reconcile
        errors = {}

        if @reason != DELETE
          errors[:admin] = reconcile_admin_roles if reconcile?(:admin)
          errors[:display_name] = reconcile_display_name if reconcile?(:display_name)
          errors[:emails] = reconcile_emails if reconcile?(:emails)
          errors[:ssh_keys] = reconcile_ssh_keys if reconcile?(:ssh_keys)
          errors[:gpg_keys] = reconcile_gpg_keys if reconcile?(:gpg_keys)
        elsif clear_profile?
          errors[:display_name] = reconcile_display_name if reconcile?(:display_name)
          errors[:emails] = reconcile_emails if reconcile?(:emails)
        end

        errors[:user_name] = reconcile_user_name if !is_enterprise_server? && reconcile?(:user_name)

        Result.new(user: user, errors: errors)
      end

      private

      # Private: A convenience method to get is_enterprise_server flag
      #
      # Returns a Boolean
      def is_enterprise_server?
        @flags[:is_enterprise_server]
      end

      # Private: A convenience method to check if the enterprise server has SCIM enabled
      #
      # Returns a Boolean
      def is_enterprise_server_scim?
        return false unless GitHub.enterprise?
        !!GitHub.global_business&.enterprise_server_scim_enabled?
      end

      # Private: A convenience method to get is_emu flag
      #
      # Returns a Boolean
      def is_emu?
        @flags[:is_emu]
      end

      # Private: A convenience method to get okta_gdpr_enabled flag
      #
      # Returns a Boolean
      def clear_profile?
        @flags[:clear_profile]
      end

      # Private: A convenience method to check the reconcile_methods array flag
      #
      # Returns a Boolean
      def reconcile?(name)
        @flags[:reconcile_methods].include?(name)
      end

      # Private: An override for fatal error generation
      def set_options(error_options)
        error_options.each do |key, value|
          @error_options[key] = value
        end
      end

      # Private: An override for flags passed into a reconciler
      def set_flags(flags)
        flags.each do |key, value|
          @flags[key] = value
        end
      end

      # Internal: Global configuration check for disabling admin functionality
      #
      # Returns true or false
      def disable_admin_demote?
        GitHub.auth.configuration[:disable_admin_demote]
      end

      # Public: Is the debug logging enabled for SAML or SCIM
      #
      # Returns true if debug logging is enabled, otherwise false
      def debug_logging_enabled?
        GitHub.config.get("saml.debug_logging_enabled") == "true"
      end

      # Private: Reconcile user name based on the value in user_data
      #
      # Returns nothing or an error condition
      def reconcile_user_name
        # This is just a precaution, this error should never fire, since the user should not be selected in
        # the code calling the reconciler.  Unless it is a patch and the selection of a user is changed to use
        # object identifier.  Setting user name to empty should result in a fatal error.
        return Error.reconciler_error(message: MISSING_LOGIN, fatal: @error_options[:missing_login]) if user_data.user_name.blank?

        login = User.standardize_login(
          self.class.user_name(user_data, suffix: user.login_suffix),
          suffix: user.login_suffix
        )

        # If the user login is the same short circuit and exit
        return if user.login == login # rubocop:disable GitHub/DoNotAllowLogin - comparing login is ok

        if user.suspended?
          # Do not rename a suspended user unless the reason is suspend or delete
          unless @reason == DELETE || @reason == SUSPEND
            return Error.reconciler_error(message: SUSPENDED_USER, fatal: @error_options[:suspended_user])
          end
        end

        # check if the user_name/login is already used, fatal error if it is
        dup_user = User.find_by_login(login)
        return Error.reconciler_error(message: LOGIN_CONFLICT, fatal: @error_options[:login_conflict]) if dup_user && dup_user.id != user.id

        log("Changing user login", "gh.user.login" => user.login, "gh.user.new_login" => login) # rubocop:disable GitHub/DoNotAllowLogin - used in logging

        # If we are unable to save rename the user, return a fatal error
        error = save_transaction(user) do
          success = user.rename(login, allow_rename: true)
          Error.reconciler_error(message: user.errors.full_messages, fatal: true) unless success
        end

        error if error
      end

      # Private: Reconcile administrator role distinguishing between private instance, enterprise server and emus
      #
      # Returns nothing or an error when setting emails failed
      def reconcile_admin_roles
        if is_enterprise_server?
          reconcile_admin
        else
          if user_data.roles.any?
            reconcile_roles
          else
            reconcile_admin
          end
        end
      end

      # Private: Reconciles a User's admin status based on the roles entry in the user data.
      # This method only runs in GHES with SCIM enabled.
      #
      # Returns nothing or an error when setting access failed
      def reconcile_roles
        return if disable_admin_demote?
        return if is_emu?
        return if GitHub.enterprise? && GitHub.global_business.enterprise_server_scim_enabled?

        roles = user_data.roles.map(&:downcase)
        enterprise_owner_roles = roles & ENTERPRISE_OWNER_ROLE
        error = save_transaction(user) do
          success = true
          business = GitHub.global_business

          if user.suspended? || (enterprise_owner_roles.empty? && user.site_admin?)
            success = demote_from_admin(user)
          elsif enterprise_owner_roles.any? && !user.site_admin?
            success = promote_to_admin(user)
          end

          Error.reconciler_error(message: "Unable to reconcile administrator") unless success
        end

        error if error
      end

      # Private: Reconciles a User's admin status based on the admin entry in the user data.
      #
      # Returns nothing or an error when setting access failed
      def reconcile_admin
        return if disable_admin_demote?

        value = user_data.admin
        # If the value was not set do nothing, return
        return if value.blank?

        # return if no changes are necessary
        return if (value&.index("true") && user.site_admin?) || (value&.index("false") && !user.site_admin?)

        error = save_transaction(user) do
          success = false
          if value&.index("true")
            success = promote_to_admin(user)
          else
            success = demote_from_admin(user)
          end

          Error.reconciler_error(message: "Unable to reconcile administrator") unless success
        end

        error if error
      end

      # Private: Promotes user to be a site administrator
      #
      # Returns boolean
      def promote_to_admin(user)
        log("promote user to admin", "gh.user.login" => user.login) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
        user.grant_site_admin_access("saml/scim single sign-on administrator promotion")
      end

      # Private: Demotes user from being a site administrator
      #
      # Returns boolean
      def demote_from_admin(user)
        log("demote user from admin", "gh.user.login" => user.login) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
        user.revoke_privileged_access("saml/scim single sign-on administrator demotion")
      end

      # Private: Reconcile a User's display name (profile  name) based on the display_name attribute in user data.
      #
      # Returns nothing or an error when setting profile name failed
      def reconcile_display_name
        # For GHES, if the display_name is not populated in the user data we should not use
        # any fallbacks to try to populate the profile name. Rather, just leave the
        # profile.name field empty or with its existing value.
        # Under no circumstances do we want to default to user_name for GHES.
        return if is_enterprise_server? && user_data.display_name.nil?

        # since we have just provisioned the user with a correct email we can skip this processing
        if is_emu? && @reason == PROVISION
          return
        end

        profile = get_user_profile
        display_name = user_data.display_name.blank? ? user_data.user_name : user_data.display_name

        # Clear the display name when the user is suspended or deleted
        unless user_data.active?
          display_name = "" if clear_profile?
        end

        return if profile.name == display_name

        record_to_save = profile.persisted? ? profile : user

        error = save_transaction(record_to_save) do
          log("changing user display name", "gh.user.display_name" => display_name, "gh.user.login" => user.login) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
          profile.name = display_name
        end

        error if error

      end

      # Private: Reconcile emails distinguishing between private instance and enterprise server
      #
      # Returns nothing or an error when setting emails failed
      def reconcile_emails
        if is_enterprise_server?
          reconcile_enterprise_server_emails
        else
          reconcile_provisioned_emails
        end
      end

      # Private: Reconcile a User's emails based on the emails from user data for enterprise server
      #          For enterprise server just add emails, never delete.  Primary email will be set if
      #          one did not exist.
      #
      # Returns nothing or an error when setting emails failed
      def reconcile_enterprise_server_emails
        # get assertion emails
        emails = user_data.emails.compact

        # get current emails and the primary email
        current_downcased_emails = user.emails.primary_first.map(&:email).map(&:downcase)
        user_primary = current_downcased_emails.first

        # compare emails
        new_emails = emails.reject { |email| current_downcased_emails.include? email.downcase }

        # short circuit if user's emails match user data entry's emails
        return if new_emails.empty?

        # build primary email if one does not exist
        email_error = nil
        if user_primary.blank?
          primary_email = new_emails.first

          if email_error = verify_and_create_primary_email(primary_email)
            return email_error if email_error.fatal?
          end
        end

        # we want to save all changes as a single transaction
        new_emails.each do |email|
          # ignore an email if it is blank
          next if email.blank?
          next if primary_email == email.downcase

          log("adding user email name", "gh.user.login" => user.login, "gh.user.email" => email) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
          user.add_email(
            email,
            rebuild_contributions: false,
          )
        end

        # rebuild contributions once for all emails added instead of for each
        # one independently
        user.rebuild_contributions(context: "reconcile_enterprise_server_emails")
        email_error
      end

      # Private: Reconcile a User's emails based on the emails from user data for private instance
      #          When no emails are present current emails will be removed to match with the IDP.
      #
      # Returns nothing or an error when setting emails failed
      def reconcile_provisioned_emails
        # since we have just provisioned the user with a correct email we can skip this processing
        if is_emu? && @reason == PROVISION
          return if user_data.emails.count == 1
        end

        # convert the array of emails to a hash keyed by an lowercase email and email in a value
        emails = Hash[user_data.emails.compact.collect { |email| [email.downcase, email] }]
        profile_email = primary_email = user_data.primary_email.presence || emails.values.first

        if is_emu?
          emails.transform_keys! { |key| user.add_emu_shortcode_to_emails(key) }
          emails.transform_values! { |value| user.add_emu_shortcode_to_emails(value) }
          primary_email = user.add_emu_shortcode_to_emails(primary_email) if primary_email.present?
        end

        # delete primary email since it will be handled differently
        emails.delete_if { |_key, value| value == primary_email }
        # obfuscate or do nothing to the other emails
        emails.transform_keys! { |key| self.class.email(user_data, key, suffix: user.login_suffix) }
        emails.transform_values! { |value| self.class.email(user_data, value, suffix: user.login_suffix) }

        # The call below will modify the primary email for a user upon suspension
        # It does not modify SCIM attributes, so the correct email is saved and can be
        # restored if the user is added back to an application
        user_primary, *user_rest = user.emails.primary_first.map(&:email)
        user_rest = Hash[user_rest.collect { |email| [email.downcase, email] }]

        unless user_data.active?
          # Prevent removal of primary email when the user is suspended
          primary_email = user.remove_shortcode(user_primary) unless primary_email.present?
          primary_email = self.class.email(user_data, primary_email, suffix: user.login_suffix)

          # Obfuscate the profile email if clear_profile is set
          profile_email = primary_email if clear_profile?

          if is_emu?
            primary_email = user.add_emu_shortcode_to_emails(primary_email)
          end
        end

        # compare emails
        new_emails = emails.reject { |key, _value| user_rest.include? key }
        old_emails = user_rest.reject { |key, _value| emails.include? key }

        primary_match = primary_email&.downcase == user_primary&.downcase
        # if user's emails do not match user data entry's emails
        unless new_emails.empty? && old_emails.empty? && primary_match
          # we want to save all changes as a single transaction
          error = save_transaction(user) do
            # set or replace primary email if they are not equal
            unless primary_match
              # verify primary email is not a duplicate, or malformed
              # save it when primary email is valid
              if email_error = verify_and_create_primary_email(primary_email)
                next email_error if email_error.fatal?
              end

              # setting primary email does not remove old primary email
              # add it to old_emails to be removed
              old_emails[user_primary.downcase] = user_primary unless user_primary.blank?

              # In GHES SCIM, we will set the secondary email as the primary if that is what the IdP sent.
              # In this scenario, the old secondary (now primary) can be removed from the old_emails to prevent it
              # from being deleted. This is a no-op if the emails were not swapped.
              if is_enterprise_server_scim?
                old_emails.delete(primary_email&.downcase)
              end
            end

            # Add new emails only
            new_emails.values.each do |email|
              # ignore an email if it is blank
              next if email.blank?
              log("adding user email name", "gh.user.login" => user.login, "gh.user.email" => email) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
              user_email = user.add_email(
                email,
                rebuild_contributions: false,
                skip_reserved_domain: @flags[:skip_reserved_domain],
              )

              # mark email as verified for emu users since an IdP is creating them
              user_email.mark_as_verified if is_emu? || !is_enterprise_server?
              # additional emails can fail, and only be partially saved
              user_email.save if user_email.valid?
            end

            # remove old emails only
            old_emails.values.each do |email|
              if is_emu?
                user.remove_email(
                  email,
                  do_not_rebuild_contributions: true
                )
              else
                user.remove_email(email)
              end

              next Error.new(reason: @reason, message: user.errors&.full_messages.to_sentence, fatal: @error_options[:remove_old_emails]) unless user.valid?
            end
          end

          return error if error && error.fatal?

          # reload the UserEmails associated with the user. This removes
          # any invalid/unsaved UserEmails
          user.emails.reload
        end

        # update profile email to primary email for a user
        profile = get_user_profile
        unless profile_match = profile.email == profile_email
          record_to_save = profile.persisted? ? profile : user

          error = save_transaction(record_to_save) do
            log("changing user profile email", "gh.user.login" => user.login, "gh.user.email" => profile_email) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
            profile.email = profile_email
          end

          return error if error
        end

        # rest the notifications email to profile email for emu
        if is_emu?
          unless profile_match
            settings_response = GitHub.newsies.settings(user)
            settings = settings_response.value!

            unless settings.email(:global).address == profile_email
              settings.email :global, profile_email
              GitHub.newsies.update_settings(user, settings)
            end
          end
        end

        # rebuild contributions once for all emails added instead of for each
        # one independently
        if is_emu?
          user_data.rebuild_contributions = !primary_match
        else
          user.rebuild_contributions(context: "reconcile_provisioned_emails")
        end
        nil
      end

      # Private: Verify and save primary email address, it will produce a fatal error message when it is not valid
      #
      # primary_email - an email to verify
      #
      # Returns an error objet when validation fails
      def verify_and_create_primary_email(primary_email)
        # Short circuit when no primary email
        return Error.new(reason: :email_taken, message: EMAILS_EMPTY, fatal: @error_options[:primary_email_blank]) if primary_email.blank?

        log("setting primary user email", "gh.user.login" => user.login, "gh.user.email" => primary_email) # rubocop:disable GitHub/DoNotAllowLogin - used in logging

        # In GHES SCIM, if we find that the email sent via SCIM is already associated with the user, but is not the
        # primary email, we will set it as the new primary email.
        primary_user_email = if is_enterprise_server_scim?
          # primary_email is the email sent by the IdP
          existing_email = user.emails.find_by_email(primary_email&.downcase)

          # Return the existing email if we find it in the user's emails. Note that we will skip this method
          # altogether if the email sent via SCIM is already the primary email.
          if existing_email
            existing_email
          # Otherwise attempt to build a new email to set as the primary.
          else
            user.emails.build(email: primary_email, skip_reserved_domain: @flags[:skip_reserved_domain])
          end
        else
          user.emails.build(email: primary_email, skip_reserved_domain: @flags[:skip_reserved_domain])
        end

        # If a invalid primary email is provided, reject the user.
        unless primary_user_email.valid?
          return Error.new(reason: :email_taken, message: EMAIL_TAKEN, fatal: @error_options[:email_taken]) if primary_user_email.duplicate?

          return Error.new(reason: @reason, message: primary_user_email.errors.full_messages.to_sentence, fatal: @error_options[:primary_email_error]) if primary_user_email.errors.full_messages.to_sentence
          return Error.new(reason: @reason, message: "Invalid primary email address.", fatal: @error_options[:primary_email_error])
        end

        # mark email as verified for emu users since an IdP is creating them
        primary_user_email.mark_as_verified if is_emu? || !is_enterprise_server?

        # This will also save the User
        status = user.set_primary_email primary_user_email
        Error.new(reason: @reason, message: status.error, fatal: @error_options[:primary_email_error])  if status.error?
      end

      # Internal: Reconcile a User's public keys.
      #
      # Returns nothing.
      def reconcile_ssh_keys
        keys = user_data.ssh_keys

        fingerprints = keys.each_with_object({}) do |k, result|
          parsed_key =
            begin
              SSHData::PublicKey.parse(k)
            rescue SSHData::Error
              log("failed to decode public key", "gh.user.login" => user.login) # rubocop:disable GitHub/DoNotAllowLogin - used in logging
              nil
            end

          next unless parsed_key

          fingerprint = parsed_key.fingerprint
          if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
            fingerprint << "_#{current_tenant.shortcode}"
          end
          result[fingerprint] = k
        end
        new_fingerprints = fingerprints.keys - user.public_keys.pluck(:fingerprint_sha256)

        errors = []
        new_fingerprints.each do |f|
          save_error = save_transaction(user) do
            user.public_keys.create_with_verification(
              key: fingerprints[f],
              verifier: user,
            )
          end
          errors += [save_error] if save_error
        end

        return if errors.count == 0
        Error.reconciler_error(message: errors.values.collect { |v| v.message }.join("\n"))
      end

      # Internal: Reconcile a User's GPG keys.
      #
      # Returns nothing.
      def reconcile_gpg_keys
        # decode the keys
        decoded_keys = user_data.gpg_keys.to_h do |key|
          decoded = GpgKey.decode_armored_public_key(key)
          if decoded["primary_key"]
            [decoded["primary_key"], key]
          else
            # invalid key skip will be skipped with compact
            [nil, nil]
          end
        end
        user_keys = user.gpg_keys.map(&:public_key)

        keys = decoded_keys.compact.reject { |key, _value| user_keys.include? key["raw_data"] }

        errors = []
        keys.values.each do |k|
          save_error = save_transaction(user) do
            user.gpg_keys.create_from_armored_public_key(k, accept_revoked_keys: true)
          end
          errors += [save_error] if save_error
        end

        return if errors.count == 0
        Error.reconciler_error(message: errors.values.collect { |v| v.message }.join("\n"))
      end

      # Private: Gets or creates user profile
      #
      # Returns Profile object
      def get_user_profile
        if user.persisted?
          user.find_or_create_profile
        else
          user.build_profile
        end
      end

      # Private: Login method that checks if the login was enabled
      #
      # Returns nothing
      def log(message, data)
        return unless debug_logging_enabled?
        GitHub::Authentication.logger.info(message, data)
      end

      # Private: Save current user data, rollback if errors were found
      #
      # Returns nothing or a fatal error
      def save_transaction(obj)
        error = nil

        obj.transaction(requires_new: true) do
          begin
            error = yield if block_given?
            raise ActiveRecord::Rollback if error && error.is_a?(Error)

            obj.save
          rescue ActiveRecord::RecordInvalid
            # revert back to previous value to restore state since it failed to rename
            error = Error.reconciler_error(message: obj.errors.first, fatal: true)
            raise ActiveRecord::Rollback
          end
        end

        error if error.is_a?(Error)
      end
    end
  end
end
