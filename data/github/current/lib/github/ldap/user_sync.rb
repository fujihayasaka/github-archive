# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    class UserSync
      include GitHub::LDAP::Instrumentable

      class SyncError < StandardError
        attr_reader :user, :object, :errors

        def initialize(user, object, errors)
          @user   = user
          @object = object
          @errors = errors
        end

        def payload
          { user: user, errors: errors }
        end
      end

      class LdapError < SyncError
        attr_reader :op, :dn, :result

        def initialize(op, dn, result)
          @op     = op
          @dn     = dn
          @result = result
        end

        def error_message
          @error ||= begin
            msg = result.message
            msg = "#{msg}: #{result.error_message}" if result.error_message.present?
            msg
          end
        end

        def message
          "LDAP operation error (#{result.code}) encountered at #{op} (#{dn}): #{error_message}"
        end

        def payload
          { op: op, dn: dn, code: result.code, result: result }
        end
      end

      class InvalidEmailError < SyncError
        def message
          "error syncing emails for #{user.login}: invalid email"
        end

        def payload
          super.merge(action: :reconcile_emails)
        end
      end

      class InvalidPublicKeyError < SyncError
        def message
          "error syncing public keys for #{user.login}: invalid key"
        end

        def payload
          super.merge(action: :reconcile_public_keys, key: object)
        end
      end

      class InvalidGpgKeyError < SyncError
        def message
          "error syncing gpg keys for #{user.login}: invalid key"
        end

        def payload
          super.merge(action: :reconcile_gpg_keys, key: object)
        end
      end

      # Public: Synchronize a User record against LDAP, reconciling differences.
      #
      # Get user data from the LDAP server and try to reconcile it.
      # If the user's login doesn't exist in the LDAP server it marks is as suspended.
      #
      # user - the User record.
      #
      # NOTE: If no LdapMapping exists but an LDAP entry matches the UID, a
      # mapping is created.
      #
      # Returns nothing.
      def perform(user)
        # When multiauth is enabled, some users will only be present in the internal
        # db and will not have a LdapMapping; don't bother trying to sync them
        return unless GitHub.auth.external_user?(user)

        map = find_ldap_mapping(user)

        unless map
          suspend(user)
          return
        end

        map.sync do |payload|
          if entry = map.entry
            payload[:entry_found] = true
            payload[:uid] = ldap.profile_info(entry, :uid)

            reconcile(user, entry)
          # user's DN has changed?
          elsif entry = find_ldap_entry(user)
            user.map_ldap_entry(entry.dn)
            user.reload_ldap_mapping

            payload[:entry_found] = true
            payload[:uid] = ldap.profile_info(entry, :uid)

            reconcile(user, entry)
          else
            if fatal_ldap_error?
              result = ldap.strategy.last_operation_result
              GitHub::Authentication::LDAP.logger.error("Sync aborted: fatal LDAP error",
                "code.namespace" => "GitHub::LDAP::UserSync",
                "code.function" => "perform",
                "code.op" => "user_search",
                "ldap.dn" => map.dn,
                "ldap.operation.result_code" => result.code,
                "ldap.operation.result.message" => result.message,
                "exception.message" => result.error_message)
              raise LdapError.new(:user_search, map.dn, result)
            else
              payload[:entry_found] = false
              suspend(user)
            end
          end

          # signal to LdapMapping if it should log activity about this sync
          payload[:ldap_fields_changed] = ldap_fields_changed
        end
      rescue SyncError => error
        Failbot.report! error, error.payload
      end

      # Reconcile users' data. Including profile, emails, ssh public keys and admin permissions.
      # It overrides user's data.
      #
      # user  - the User in database
      # entry - the Net::LDAP::Entry with user data from the LDAP server
      #
      # Returns a collection of outputs to keep in the hunt's log.
      def reconcile(user, entry)
        ldap_authorization = ldap.ldap_authorization(entry)
        ldap.reconcile_access(user, ldap_authorization, reactivate_suspended_user: GitHub.reactivate_suspended_user_on_sync?)
        return unless ldap_authorization.valid? && !user.suspended?

        reconcile_profile(user, entry)
        reconcile_admin(user, entry)

        reconcile_emails(user, entry)
        reconcile_public_keys(user, entry)
        reconcile_gpg_keys(user, entry)

        user.save!
      end

      # Suspend user when her login is not in the LDAP server. Will also demote
      # user.
      #
      # user - the user in database
      #
      # Returns a string to keep in the hunt's log.
      def suspend(user, reason = "#{user.login} not found in the LDAP server, marked as suspended")
        return if allowlisted?(user)
        user.revoke_privileged_access(reason) if user.site_admin?
        user.suspend(reason) if !user.suspended?
      end

      def ldap
        GitHub.auth
      end

      # Public: Returns the LdapMapping for a given User, or nil.
      def find_ldap_mapping(user)
        return user.ldap_mapping if user.ldap_mapping

        if entry = find_ldap_entry(user)
          user.map_ldap_entry(entry.dn)
          user.reload_ldap_mapping
        end
      end

      # Public: Returns a matching Net::LDAP::Entry for the User, or nil.
      def find_ldap_entry(user)
        ldap.ldap_domains.each_value do |domain|
          fallback_uid = user.ldap_mapping && user.ldap_mapping.fallback_uid
          entry        = domain.user?(fallback_uid || user.login)

          return entry if entry
        end

        nil # explicit fallback
      end

      # Internal: Reconcile a User's profile based on the Net::LDAP::Entry.
      #
      # Returns nothing.
      def reconcile_profile(user, entry)
        cn = ldap.profile_info(entry, :name)

        unless cn.empty?
          user.profile_name = GitHub::Encoding.guess_and_transcode(cn.first)
          log_ldap_sync!("profile") if user.profile.changed?
          user.update_profile
        end
      end

      # Internal: Reconcile a User's admin status based on the Net::LDAP::Entry
      # and its inclusion in the configured LDAP admin group.
      #
      # Returns nothing.
      def reconcile_admin(user, entry)
        return unless GitHub.ldap_admin_group

        admin = ldap.is_admin?(entry)

        if admin && !user.site_admin?
          user.grant_site_admin_access("User #{user.login} belongs to the admin group: #{GitHub.ldap_admin_group}")
          log_ldap_sync!("site_admin_granted")
        end
        if !admin && user.site_admin?
          user.revoke_privileged_access("User #{user.login} doesn't belong to the admin group anymore: #{GitHub.ldap_admin_group}")
          log_ldap_sync!("site_admin_revoked")
        end
      end

      # Internal: Reconcile a User's emails based on the Net::LDAP::Entry.
      #
      # Returns nothing. Raises InvalidEmailError.
      def reconcile_emails(user, entry)
        return unless ldap.emails_managed_externally?

        emails = ldap.profile_info(entry, :mail).uniq

        # short circuit if user's emails match LDAP entry's emails
        return if emails_synced?(user, emails)

        log_ldap_sync!("emails")

        # purge all previous emails and roles
        # prevents EmailRole::CannotDeleteLastPrimaryEmail guard from raising
        user.email_roles.delete_all
        user.emails.destroy_all

        emails.each_with_index do |email, idx|
          is_primary = idx == 0
          begin
            user_email = user.add_email email,
              is_primary: is_primary, rebuild_contributions: false

            unless user_email.valid?
              raise InvalidEmailError.new(user, email, user_email.errors.full_messages)
            end
          rescue ActiveRecord::RecordInvalid => error
            message = error.message
            if user_email = user.emails.first
              message = "#{message} (#{user_email.errors.full_messages})"
            end
            raise InvalidEmailError.new(user, email, message)
          end
        end

        # rebuild contributions once for all emails added instead of for each
        # one independently
        user.rebuild_contributions
      end

      # Internal: Reconcile a User's public keys based on the Net::LDAP::Entry.
      #
      # Returns nothing. Raises InvalidPublicKeyError.
      def reconcile_public_keys(user, entry)
        return unless GitHub.auth.ssh_keys_managed_externally?

        # retrieve keys and normalize whitespace/comments for comparison,
        # rejecting keys with known non-SSH public key prefixes
        keys = ldap.profile_info(entry, :key)

        ids_before_sync = user.public_keys.map(&:id)
        self.class.sync_public_keys(user, keys)

        if ids_before_sync != user.public_keys.map(&:id)
          log_ldap_sync!("public_keys")
        end
      end

      # Internal
      #
      # Sync SSH Public Keys, used for both LDAP Sync and initial user creation via LDAP
      def self.sync_public_keys(user, keys)
        keys.reject! { |key| has_non_ssh_prefix?(key) }
        keys.map!    { |key| PublicKey.normalize_key(key) }
        # blank keys are not valid and can be sent by some LDAP servers when the sshPublicKey attribute is required
        # and then set / unset
        # see https://github.com/github/external-identities/issues/3393
        if GitHub.ldap_user_sync_skip_empty_keys
          keys.reject! { |key| key.empty? }
        end

        user.public_keys.to_a.dup.each do |key|
          user.public_keys.delete(key) unless keys.include?(key.key)
          keys.delete(key.key)
        end

        keys.each do |key|
          unless user.add_public_key(key)
            pk = user.public_keys.find { |pk| !pk.valid? }
            errors = pk ? pk.errors.full_messages : []
            raise InvalidPublicKeyError.new(user, key, errors)
          end
        end
        user.public_keys.each do |k|
          k.verify(user)   # auto-verify keys added by LDAP
        end

        user.save
      end

      NON_SSH_PREFIXES = %w(X509: Kerberos:)

      # Internal: Identify if a key begins with a valid, known, non-SSH public
      # key prefix.
      #
      # See https://github.com/github/github/issues/39396 for details.
      def self.has_non_ssh_prefix?(key)
        NON_SSH_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      end

      # Internal: Reconcile a User's GPG keys based on the Net::LDAP::Entry.
      #
      # Returns nothing. Raises InvalidGPGKeyError.
      def reconcile_gpg_keys(user, entry)
        return unless GitHub.auth.gpg_keys_managed_externally?

        # retrieve keys and normalize whitespace/comments for comparison,
        # rejecting non GPG keys
        keys = ldap.profile_info(entry, :gpgkey)

        keys_before_sync = user.gpg_keys.map(&:id)
        self.class.sync_gpg_keys(user, keys)

        if keys_before_sync != user.gpg_keys.map(&:id)
          log_ldap_sync!("gpg_keys")
        end
      end

      # Internal
      #
      # Sync GPG keys, used for both LDAP sync and authentication
      def self.sync_gpg_keys(user, keys)
        keys.select! { |key| has_gpg_armored_key_prefix?(key) }

        incoming_gpg_keys = keys.map.to_h do |key|
          decoded = GpgKey.decode_armored_public_key(key)
          if decoded["primary_key"]
            [decoded["primary_key"], key]
          else
            errors = decoded ? decoded.errors.full_messages : []
            raise InvalidGpgKeyError.new(user, key, errors)
          end
        end

        existing_gpg_keys = user.gpg_keys.index_by(&:public_key)
        to_add_gpg_keys = incoming_gpg_keys.reject { |key, _value| existing_gpg_keys.keys.include?(key["raw_data"]) }

        to_add_gpg_keys.values.each do |gpg_key|
          user.gpg_keys.create_from_armored_public_key(gpg_key, accept_revoked_keys: true)
        end

        incoming_gpg_public_keys = incoming_gpg_keys.keys.map { |key| key["raw_data"] }
        to_remove_gpg_keys = existing_gpg_keys.reject { |key, _value| incoming_gpg_public_keys.include?(key) }

        to_remove_gpg_keys.values.each do |gpg_key|
          user.gpg_keys.delete(gpg_key)
        end
      end

      def self.has_gpg_armored_key_prefix?(key)
        key.start_with?("-----BEGIN PGP PUBLIC KEY BLOCK-----")
      end

      # Internal - Check if the user is allowlisted from being suspended when she doesn't have an ldap mapping.
      #
      # user: is a User to suspend.
      #
      # Returns true if the user can be excluded from suspension.
      # Returns false if the user needs to be suspended.
      def allowlisted?(user)
        @allowlist ||= [User.ghost, first_admin_user]

        @allowlist.include? user
      end

      # Internal: Verifies that the User's emails match the LDAP entry's
      # emails.
      #
      # Returns true if the primary email matches up and the rest of the emails
      # are accounted for.
      def emails_synced?(user, emails)
        # gather emails as Strings, separating the primary
        ldap_primary, *ldap_rest = emails
        user_primary, *user_rest = user.emails.primary_first.map(&:email)

        # compare the primaries as Strings, and the rest as Sets (order doesn't matter)
        primary_match = ldap_primary == user_primary
        rest_match    = Set.new(ldap_rest) == Set.new(user_rest)

        # validate both primary and rest match between LDAP and User record
        primary_match && rest_match
      end

      # Internal - Fist admin user created.
      #
      # Pre 11.10.340 there was an admin user created manually for recovery.
      # This user is unlikely to map any ldap entry.
      # This user still can be suspended via stafftools if it's necessary.
      #
      # Post 11.10.340 the first user that logs in in the installation is considered this admin user.
      # The ldap mapping is always created after logging in in this case, which will make this
      # method irrelevant for installations that start from scratch.
      #
      # Returns the first admin user created in the system.
      def first_admin_user
        User.where("type = 'User' and gh_role = 'staff'").first
      end

      FATAL_LDAP_ERRORS = [
        Net::LDAP::ResultCodeOperationsError,
        Net::LDAP::ResultCodeProtocolError,
        Net::LDAP::ResultCodeTimeLimitExceeded,
        Net::LDAP::ResultCodeSizeLimitExceeded,
        Net::LDAP::ResultCodeInvalidCredentials,
        Net::LDAP::ResultCodeInsufficientAccessRights,
        Net::LDAP::ResultCodeUnavailable,
        Net::LDAP::ResultCodeUnwillingToPerform,
        Net::LDAP::ResultCodeOther,
      ]

      # Internal: Check if there was a fatal error with the last LDAP operation.
      def fatal_ldap_error?
        FATAL_LDAP_ERRORS.include?(ldap.strategy.last_operation_result.code)
      end
      private :fatal_ldap_error?
    end
  end
end
